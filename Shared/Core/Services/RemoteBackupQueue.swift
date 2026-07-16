import Foundation

typealias RemoteBackupProviderFactory = @Sendable (
    RemoteDestinationProfile,
    RemoteCredential
) async throws -> any RemoteBackupProvider

/// Owns a temporary authorization to use a verified local artifact. The
/// queue releases it in `defer`, including provider failures and cancellation.
final class RemoteBackupArtifactLease: @unchecked Sendable {
    let url: URL
    private let releaseAccess: @Sendable () -> Void
    private let lock = NSLock()
    private var released = false

    init(url: URL, releaseAccess: @escaping @Sendable () -> Void) {
        self.url = url
        self.releaseAccess = releaseAccess
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard !released else { return }
        released = true
        releaseAccess()
    }
}

typealias RemoteBackupLocalArtifactResolver = @Sendable (RemoteQueueItem) async throws -> RemoteBackupArtifactLease

/// The persistent data boundary used by `RemoteBackupQueue`. The production
/// adapter delegates to the Task 2 profile, manifest, queue-item, and Keychain
/// stores; providers and tests use this neutral boundary instead.
protocol RemoteBackupQueuePersistence: Sendable {
    func jobs() async throws -> [PhotographerJob]
    func profiles() async throws -> [RemoteDestinationProfile]
    func manifests() async throws -> [RemoteManifest]
    func queueItems() async throws -> [RemoteQueueItem]
    func credential(for profileID: UUID) async throws -> RemoteCredential?
    func save(_ item: RemoteQueueItem) async throws
    func deleteQueueItem(id: UUID) async throws
}

@MainActor
final class PhotographerJobStoreRemoteBackupQueuePersistence: RemoteBackupQueuePersistence {
    private let store: any PhotographerJobStore
    private let credentialStore: RemoteCredentialStore

    init(
        store: any PhotographerJobStore,
        credentialStore: RemoteCredentialStore = RemoteCredentialStore()
    ) {
        self.store = store
        self.credentialStore = credentialStore
    }

    func jobs() async throws -> [PhotographerJob] { try store.jobs() }
    func profiles() async throws -> [RemoteDestinationProfile] { try store.profiles() }
    func manifests() async throws -> [RemoteManifest] { try store.manifests() }
    func queueItems() async throws -> [RemoteQueueItem] { try store.queueItems() }
    func credential(for profileID: UUID) async throws -> RemoteCredential? {
        try credentialStore.credential(for: profileID)
    }
    func save(_ item: RemoteQueueItem) async throws { try store.save(item) }
    func deleteQueueItem(id: UUID) async throws { try store.deleteQueueItem(id: id) }
}

actor RemoteBackupQueue {
    private let persistence: any RemoteBackupQueuePersistence
    private let providerFactory: RemoteBackupProviderFactory
    private let localArtifactResolver: RemoteBackupLocalArtifactResolver
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> TimeInterval
    private var items: [UUID: RemoteQueueItem] = [:]
    private var runningItemIDs = Set<UUID>()
    private var cancellingItemIDs = Set<UUID>()
    private var mutationGenerations: [UUID: UInt64] = [:]
    private var pendingWrites: [UUID: Task<Void, Error>] = [:]

    init(
        persistence: any RemoteBackupQueuePersistence,
        providerFactory: @escaping RemoteBackupProviderFactory,
        localArtifactResolver: @escaping RemoteBackupLocalArtifactResolver,
        now: @escaping @Sendable () -> Date = { Date() },
        jitter: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0 ... 1) }
    ) {
        self.persistence = persistence
        self.providerFactory = providerFactory
        self.localArtifactResolver = localArtifactResolver
        self.now = now
        self.jitter = jitter
    }

    /// Restores queue items before returning. Existing in-memory mutations win
    /// over a snapshot that was read before they were durably saved.
    func restore() async throws {
        let persistedItems = try await persistence.queueItems()
        for item in persistedItems where items[item.id] == nil {
            items[item.id] = item
        }
    }

    /// Makes an item durable before it becomes runnable in memory.
    func enqueue(_ item: RemoteQueueItem) async throws {
        try await saveSerially(item)
        items[item.id] = item
    }

    func run(_ id: UUID) async {
        guard !runningItemIDs.contains(id), isRunnable(id) else { return }
        runningItemIDs.insert(id)
        defer { runningItemIDs.remove(id) }

        do {
            guard let item = items[id] else { return }
            // Fail closed on the local artifact before credentials, provider
            // construction, or provider preflight. This short validation lease
            // is released before any provider exists; the upload lease below is
            // separately acquired immediately before provider file access.
            let validationLease = try await localArtifactResolver(item)
            validationLease.release()
            let context = try await validatedContext(for: item)
            guard isRunnable(id) else { return }
            guard let credential = try await persistence.credential(for: context.profile.id) else {
                throw RemoteBackupError.missingCredential
            }
            let provider = try await providerFactory(context.profile, credential)
            do {
                // Authorization starts only after preflight and is held only
                // while the provider can read the local file (upload through
                // remote verification). The lease is released on every exit.
                let capabilities = try await provider.preflight(profile: context.profile, credential: credential)
                guard isRunnable(id) else {
                    await provider.close()
                    return
                }
                if let requirement = capabilities.missingRequirements(for: context.profile.verificationMode).first {
                    throw RemoteBackupError.capabilityUnavailable(requirement)
                }
                // Re-resolve after preflight so the URL passed to the provider
                // has fresh evidence and an active security-scoped lease.
                let lease = try await localArtifactResolver(item)
                defer { lease.release() }
                guard isRunnable(id) else {
                    await provider.close()
                    return
                }
                try await run(
                    itemID: id,
                    profile: context.profile,
                    credential: credential,
                    localURL: lease.url,
                    manifestEntry: context.manifestEntry,
                    provider: provider
                )
                await provider.close()
            } catch {
                await provider.close()
                throw error
            }
        } catch {
            await handle(error: error, itemID: id)
        }
    }

    /// Cancellation is persisted before this method returns. A running remote
    /// operation may finish at the provider, but it cannot overwrite this state.
    func cancel(_ id: UUID) async throws {
        guard items[id] != nil else { return }
        cancellingItemIDs.insert(id)
        _ = try await transition(itemID: id, allowingCancellation: true) { item in
            item.state = .cancelled
            item.nextAttemptAt = nil
            item.errorSummary = RemoteBackupError.cancelled.errorDescription
        }
    }

    func item(id: UUID) -> RemoteQueueItem? { items[id] }

    private func run(
        itemID: UUID,
        profile: RemoteDestinationProfile,
        credential: RemoteCredential,
        localURL: URL,
        manifestEntry: RemoteManifestEntry,
        provider: any RemoteBackupProvider
    ) async throws {
        guard let item = items[itemID] else { return }

        let existingFinal = try await provider.inspect(path: item.remoteRelativePath)
        guard isRunnable(itemID) else { return }
        if let existingFinal {
            guard item.state == .verifying else {
                _ = try await transition(itemID: itemID) { queuedItem in
                    queuedItem.state = .conflict
                    queuedItem.nextAttemptAt = nil
                    queuedItem.errorSummary = RemoteBackupError.conflict.errorDescription
                }
                return
            }
            guard existingFinal.byteCount == manifestEntry.byteCount else {
                throw RemoteBackupError.verificationFailed
            }
            try await finalizeOwnedFinal(
                itemID: itemID,
                profile: profile,
                manifestEntry: manifestEntry,
                provider: provider
            )
            return
        }

        let remoteTemporaryByteCount = try await provider.inspect(path: item.temporaryRemoteRelativePath)?.byteCount ?? 0
        guard isRunnable(itemID) else { return }

        // `.verifying` is the durable promotion-intent marker. It is written
        // before promotion, so a crash after promotion can only resume finalization.
        if item.state == .verifying {
            guard remoteTemporaryByteCount == manifestEntry.byteCount else {
                throw RemoteBackupError.resumeOffsetMismatch(
                    local: manifestEntry.byteCount,
                    remote: remoteTemporaryByteCount
                )
            }
            try await promoteAndFinalize(
                itemID: itemID,
                profile: profile,
                manifestEntry: manifestEntry,
                provider: provider
            )
            return
        }

        guard item.uploadedByteCount == remoteTemporaryByteCount else {
            throw RemoteBackupError.resumeOffsetMismatch(
                local: item.uploadedByteCount,
                remote: remoteTemporaryByteCount
            )
        }

        if item.remoteRelativePath.components.count > 1 {
            let parent = try RemoteRelativePath(components: Array(item.remoteRelativePath.components.dropLast()))
            try await provider.ensureDirectory(parent)
            guard isRunnable(itemID) else { return }
        }

        guard try await transition(itemID: itemID, { queuedItem in
            queuedItem.state = .uploading
            queuedItem.uploadedByteCount = remoteTemporaryByteCount
            queuedItem.nextAttemptAt = nil
            queuedItem.errorSummary = nil
        }) else { return }

        try await provider.upload(
            local: localURL,
            toTemporary: item.temporaryRemoteRelativePath,
            fromOffset: remoteTemporaryByteCount,
            progress: { [weak self] byteCount in
                await self?.recordProgress(itemID: itemID, byteCount: byteCount)
            }
        )
        guard isRunnable(itemID) else { return }

        let completedTemporaryByteCount = try await provider.inspect(path: item.temporaryRemoteRelativePath)?.byteCount ?? 0
        guard isRunnable(itemID) else { return }
        guard completedTemporaryByteCount == manifestEntry.byteCount else {
            throw RemoteBackupError.resumeOffsetMismatch(
                local: manifestEntry.byteCount,
                remote: completedTemporaryByteCount
            )
        }

        guard try await transition(itemID: itemID, { queuedItem in
            queuedItem.state = .verifying
            queuedItem.uploadedByteCount = manifestEntry.byteCount
            queuedItem.nextAttemptAt = nil
            queuedItem.errorSummary = nil
        }) else { return }

        try await promoteAndFinalize(
            itemID: itemID,
            profile: profile,
            manifestEntry: manifestEntry,
            provider: provider
        )
    }

    private func promoteAndFinalize(
        itemID: UUID,
        profile: RemoteDestinationProfile,
        manifestEntry: RemoteManifestEntry,
        provider: any RemoteBackupProvider
    ) async throws {
        guard let item = items[itemID], isRunnable(itemID) else { return }
        try await provider.promoteNoReplace(
            temporary: item.temporaryRemoteRelativePath,
            final: item.remoteRelativePath
        )
        guard isRunnable(itemID) else { return }
        try await finalizeOwnedFinal(
            itemID: itemID,
            profile: profile,
            manifestEntry: manifestEntry,
            provider: provider
        )
    }

    private func finalizeOwnedFinal(
        itemID: UUID,
        profile: RemoteDestinationProfile,
        manifestEntry: RemoteManifestEntry,
        provider: any RemoteBackupProvider
    ) async throws {
        guard isRunnable(itemID) else { return }
        guard profile.verificationMode == .sha256 else {
            _ = try await transition(itemID: itemID) { queuedItem in
                queuedItem.state = .uploadedUnverified
                queuedItem.uploadedByteCount = manifestEntry.byteCount
                queuedItem.nextAttemptAt = nil
                queuedItem.verificationEvidence = .none
                queuedItem.errorSummary = nil
            }
            return
        }

        let evidence = try await provider.verificationEvidence(
            for: items[itemID]?.remoteRelativePath ?? manifestEntry.relativePath,
            expectedSHA256: manifestEntry.sha256
        )
        guard isRunnable(itemID) else { return }
        guard evidence.digest?.caseInsensitiveCompare(manifestEntry.sha256) == .orderedSame else {
            throw RemoteBackupError.verificationFailed
        }
        _ = try await transition(itemID: itemID) { queuedItem in
            queuedItem.state = .verified
            queuedItem.uploadedByteCount = manifestEntry.byteCount
            queuedItem.nextAttemptAt = nil
            queuedItem.verificationEvidence = evidence
            queuedItem.errorSummary = nil
        }
    }

    private func validatedContext(for item: RemoteQueueItem) async throws -> (
        profile: RemoteDestinationProfile,
        manifestEntry: RemoteManifestEntry
    ) {
        async let profiles = persistence.profiles()
        async let manifests = persistence.manifests()
        async let jobs = persistence.jobs()
        let (savedProfiles, savedManifests, savedJobs) = try await (profiles, manifests, jobs)
        guard let profile = savedProfiles.first(where: { $0.id == item.destinationProfileID }),
              let manifest = savedManifests.first(where: { $0.id == item.manifestID }),
              manifest.pendingCleanupBookmarkReference == nil,
              manifest.destinationProfileID == profile.id,
              manifest.jobID == item.jobID,
              manifest.cardIngestID == item.cardIngestID,
              let job = savedJobs.first(where: { $0.id == item.jobID }),
              job.cardIngests.contains(where: { $0.id == item.cardIngestID }),
              let entry = manifest.entries.first(where: { $0.id == item.manifestEntryID }),
              entry.relativePath == item.localArtifactRelativePath,
              item.remoteRelativePath == (try expectedFinalPath(manifest: manifest, entry: entry)),
              item.temporaryRemoteRelativePath == (try expectedTemporaryPath(
                  final: item.remoteRelativePath,
                  itemID: item.id
              )),
              item.localArtifactBookmarkReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              entry.byteCount >= 0,
              isSHA256(entry.sha256) else {
            throw RemoteBackupError.manifestUnavailable
        }
        return (profile, entry)
    }

    /// Provider paths are always relative to the selected profile root. The
    /// final path is immutable manifest package + entry identity; it is never
    /// trusted from the persisted queue item.
    private func expectedFinalPath(
        manifest: RemoteManifest,
        entry: RemoteManifestEntry
    ) throws -> RemoteRelativePath {
        try manifest.packageRelativePath.appending(path: entry.relativePath)
    }

    private func expectedTemporaryPath(
        final: RemoteRelativePath,
        itemID: UUID
    ) throws -> RemoteRelativePath {
        let parent = try RemoteRelativePath(components: Array(final.components.dropLast()))
        return try parent.appending(".bitmatch-upload-\(itemID.uuidString.lowercased())")
    }

    private func recordProgress(itemID: UUID, byteCount: Int64) async {
        guard byteCount >= 0 else { return }
        do {
            _ = try await transition(itemID: itemID) { item in
                item.uploadedByteCount = max(item.uploadedByteCount, byteCount)
            }
        } catch {
            await handle(error: error, itemID: itemID)
        }
    }

    private func handle(error: Error, itemID: UUID) async {
        guard !cancellingItemIDs.contains(itemID), let item = items[itemID] else { return }
        let backupError = (error as? RemoteBackupError) ?? .providerUnavailable

        do {
            if backupError.isTransientNetworkFault {
                let retryCount = item.retryCount + 1
                let delay = retryDelay(for: retryCount)
                _ = try await transition(itemID: itemID) { queuedItem in
                    queuedItem.state = item.state == .verifying ? .verifying : .retrying
                    queuedItem.retryCount = retryCount
                    queuedItem.nextAttemptAt = now().addingTimeInterval(delay)
                    queuedItem.errorSummary = backupError.errorDescription
                }
            } else {
                _ = try await transition(itemID: itemID) { queuedItem in
                    // Keep the promotion-intent marker only for recoverable
                    // verification/promotion interruptions. Invalid persisted
                    // linkage, a digest mismatch, conflict, or resume
                    // disagreement clears it and fails closed.
                    if item.state != .verifying || clearsPromotionIntent(backupError) {
                        queuedItem.state = backupError.failClosedState
                    }
                    queuedItem.nextAttemptAt = nil
                    queuedItem.errorSummary = backupError.errorDescription
                }
            }
        } catch {
            // A persistence failure never permits an in-memory upload retry.
        }
    }

    private func retryDelay(for retryCount: Int) -> TimeInterval {
        let cappedBase = min(300, pow(2, Double(max(0, retryCount - 1))))
        return min(300, cappedBase + max(0, min(jitter(), cappedBase * 0.25)))
    }

    private func isRunnable(_ id: UUID) -> Bool {
        guard let item = items[id], !cancellingItemIDs.contains(id) else { return false }
        guard !item.state.isTerminal else { return false }
        return item.nextAttemptAt.map { $0 <= now() } ?? true
    }

    private func transition(
        itemID: UUID,
        allowingCancellation: Bool = false,
        _ change: (inout RemoteQueueItem) -> Void
    ) async throws -> Bool {
        guard var updatedItem = items[itemID], allowingCancellation || !cancellingItemIDs.contains(itemID) else {
            return false
        }
        change(&updatedItem)
        updatedItem.updatedAt = now()
        let generation = nextMutationGeneration(for: itemID)
        try await saveSerially(updatedItem)
        guard mutationGenerations[itemID] == generation else { return false }
        items[itemID] = updatedItem
        return true
    }

    private func nextMutationGeneration(for itemID: UUID) -> UInt64 {
        let generation = (mutationGenerations[itemID] ?? 0) &+ 1
        mutationGenerations[itemID] = generation
        return generation
    }

    private func saveSerially(_ item: RemoteQueueItem) async throws {
        let priorWrite = pendingWrites[item.id]
        let persistence = persistence
        let write = Task<Void, Error> {
            if let priorWrite {
                _ = try? await priorWrite.value
            }
            try await persistence.save(item)
        }
        pendingWrites[item.id] = write
        try await write.value
    }

    private func isSHA256(_ digest: String) -> Bool {
        digest.utf8.count == 64 && digest.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private func clearsPromotionIntent(_ error: RemoteBackupError) -> Bool {
        switch error {
        case .manifestUnavailable, .verificationFailed, .conflict, .resumeOffsetMismatch:
            return true
        default:
            return false
        }
    }
}

private extension RemoteBackupState {
    var isTerminal: Bool {
        switch self {
        case .uploadedUnverified, .verified, .failed, .cancelled, .conflict:
            return true
        case .queued, .uploading, .retrying, .paused, .verifying:
            return false
        }
    }
}
