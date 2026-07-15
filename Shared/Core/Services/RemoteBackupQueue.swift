import Foundation

typealias RemoteBackupProviderFactory = @Sendable (
    RemoteDestinationProfile,
    RemoteCredential
) async throws -> any RemoteBackupProvider

typealias RemoteBackupLocalArtifactResolver = @Sendable (RemoteQueueItem) async throws -> URL

/// The persistent data boundary used by `RemoteBackupQueue`. The production
/// adapter delegates to the Task 2 profile, manifest, queue-item, and Keychain
/// stores; providers and tests use this neutral boundary instead.
protocol RemoteBackupQueuePersistence: Sendable {
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

    func profiles() async throws -> [RemoteDestinationProfile] {
        try store.profiles()
    }

    func manifests() async throws -> [RemoteManifest] {
        try store.manifests()
    }

    func queueItems() async throws -> [RemoteQueueItem] {
        try store.queueItems()
    }

    func credential(for profileID: UUID) async throws -> RemoteCredential? {
        try credentialStore.credential(for: profileID)
    }

    func save(_ item: RemoteQueueItem) async throws {
        try store.save(item)
    }

    func deleteQueueItem(id: UUID) async throws {
        try store.deleteQueueItem(id: id)
    }
}

actor RemoteBackupQueue {
    private let persistence: any RemoteBackupQueuePersistence
    private let providerFactory: RemoteBackupProviderFactory
    private let localArtifactResolver: RemoteBackupLocalArtifactResolver
    private let now: @Sendable () -> Date
    private let jitter: @Sendable () -> TimeInterval
    private var items: [UUID: RemoteQueueItem] = [:]

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

    /// Loads the Task 2 persisted queue. Interrupted uploads retain their saved
    /// offset and are checked against the server before any resume attempt.
    func restore() {
        Task { [weak self] in
            await self?.restorePersistedItems()
        }
    }

    func enqueue(_ item: RemoteQueueItem) {
        items[item.id] = item
        Task { [weak self] in
            await self?.persistEnqueuedItem(item)
        }
    }

    func run(_ id: UUID) async {
        guard let item = items[id], !item.state.isTerminal else { return }
        guard item.nextAttemptAt.map({ $0 <= now() }) ?? true else { return }

        do {
            let profile = try await profile(for: item)
            guard let credential = try await persistence.credential(for: profile.id) else {
                throw RemoteBackupError.missingCredential
            }
            let localURL = try await localArtifactResolver(item)
            let manifestEntry = try await manifestEntry(for: item)
            let provider = try await providerFactory(profile, credential)

            do {
                try await run(
                    itemID: id,
                    profile: profile,
                    credential: credential,
                    localURL: localURL,
                    manifestEntry: manifestEntry,
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

    func cancel(_ id: UUID) {
        guard items[id] != nil else { return }
        Task { [weak self] in
            await self?.persistCancellation(id)
        }
    }

    func item(id: UUID) -> RemoteQueueItem? {
        items[id]
    }

    private func restorePersistedItems() async {
        do {
            let persistedItems = try await persistence.queueItems()
            items = Dictionary(uniqueKeysWithValues: persistedItems.map { ($0.id, $0) })
        } catch {
            // No in-memory queue is safer than guessing at unavailable persistent state.
            items = [:]
        }
    }

    private func persistEnqueuedItem(_ item: RemoteQueueItem) async {
        do {
            try await persistence.save(item)
        } catch {
            await handle(error: error, itemID: item.id)
        }
    }

    private func persistCancellation(_ id: UUID) async {
        do {
            try await transition(itemID: id) { item in
                item.state = .cancelled
                item.nextAttemptAt = nil
                item.errorSummary = RemoteBackupError.cancelled.errorDescription
            }
        } catch {
            await handle(error: error, itemID: id)
        }
    }

    private func run(
        itemID: UUID,
        profile: RemoteDestinationProfile,
        credential: RemoteCredential,
        localURL: URL,
        manifestEntry: RemoteManifestEntry,
        provider: any RemoteBackupProvider
    ) async throws {
        let capabilities = try await provider.preflight(profile: profile, credential: credential)
        if let requirement = capabilities.missingRequirements(for: profile.verificationMode).first {
            throw RemoteBackupError.capabilityUnavailable(requirement)
        }

        guard let item = items[itemID] else { return }
        if try await provider.inspect(path: item.remoteRelativePath) != nil {
            try await transition(itemID: itemID) { queuedItem in
                queuedItem.state = .conflict
                queuedItem.nextAttemptAt = nil
                queuedItem.errorSummary = RemoteBackupError.conflict.errorDescription
            }
            return
        }

        let remoteTemporaryByteCount = try await provider.inspect(path: item.temporaryRemoteRelativePath)?.byteCount ?? 0
        guard item.uploadedByteCount == remoteTemporaryByteCount else {
            throw RemoteBackupError.resumeOffsetMismatch(
                local: item.uploadedByteCount,
                remote: remoteTemporaryByteCount
            )
        }

        if item.remoteRelativePath.components.count > 1 {
            let parent = try RemoteRelativePath(components: Array(item.remoteRelativePath.components.dropLast()))
            try await provider.ensureDirectory(parent)
        }

        try await transition(itemID: itemID) { queuedItem in
            queuedItem.state = .uploading
            queuedItem.uploadedByteCount = remoteTemporaryByteCount
            queuedItem.nextAttemptAt = nil
            queuedItem.errorSummary = nil
        }

        try await provider.upload(
            local: localURL,
            toTemporary: item.temporaryRemoteRelativePath,
            fromOffset: remoteTemporaryByteCount,
            progress: { [weak self] byteCount in
                await self?.recordProgress(itemID: itemID, byteCount: byteCount)
            }
        )

        let completedTemporaryByteCount = try await provider.inspect(path: item.temporaryRemoteRelativePath)?.byteCount ?? 0
        guard completedTemporaryByteCount == manifestEntry.byteCount else {
            throw RemoteBackupError.resumeOffsetMismatch(
                local: manifestEntry.byteCount,
                remote: completedTemporaryByteCount
            )
        }

        try await provider.promoteNoReplace(
            temporary: item.temporaryRemoteRelativePath,
            final: item.remoteRelativePath
        )

        guard profile.verificationMode == .sha256 else {
            try await transition(itemID: itemID) { queuedItem in
                queuedItem.state = .uploadedUnverified
                queuedItem.uploadedByteCount = manifestEntry.byteCount
                queuedItem.nextAttemptAt = nil
                queuedItem.verificationEvidence = .none
                queuedItem.errorSummary = nil
            }
            return
        }

        try await transition(itemID: itemID) { queuedItem in
            queuedItem.state = .verifying
            queuedItem.nextAttemptAt = nil
            queuedItem.errorSummary = nil
        }
        let evidence = try await provider.verificationEvidence(
            for: item.remoteRelativePath,
            expectedSHA256: manifestEntry.sha256
        )
        guard evidence.digest?.caseInsensitiveCompare(manifestEntry.sha256) == .orderedSame else {
            throw RemoteBackupError.verificationFailed
        }
        try await transition(itemID: itemID) { queuedItem in
            queuedItem.state = .verified
            queuedItem.uploadedByteCount = manifestEntry.byteCount
            queuedItem.nextAttemptAt = nil
            queuedItem.verificationEvidence = evidence
            queuedItem.errorSummary = nil
        }
    }

    private func manifestEntry(for item: RemoteQueueItem) async throws -> RemoteManifestEntry {
        let manifests = try await persistence.manifests()
        guard let manifest = manifests.first(where: { $0.id == item.manifestID }),
              let entry = manifest.entries.first(where: { $0.id == item.manifestEntryID }) else {
            throw RemoteBackupError.manifestUnavailable
        }
        return entry
    }

    private func profile(for item: RemoteQueueItem) async throws -> RemoteDestinationProfile {
        let profiles = try await persistence.profiles()
        guard let profile = profiles.first(where: { $0.id == item.destinationProfileID }) else {
            throw RemoteBackupError.missingProfile
        }
        return profile
    }

    private func recordProgress(itemID: UUID, byteCount: Int64) async {
        guard byteCount >= 0 else { return }
        do {
            try await transition(itemID: itemID) { item in
                item.uploadedByteCount = max(item.uploadedByteCount, byteCount)
            }
        } catch {
            await handle(error: error, itemID: itemID)
        }
    }

    private func handle(error: Error, itemID: UUID) async {
        let backupError = (error as? RemoteBackupError) ?? .providerUnavailable

        do {
            if backupError.isTransientNetworkFault, let item = items[itemID] {
                let retryCount = item.retryCount + 1
                let delay = retryDelay(for: retryCount)
                try await transition(itemID: itemID) { queuedItem in
                    queuedItem.state = .retrying
                    queuedItem.retryCount = retryCount
                    queuedItem.nextAttemptAt = now().addingTimeInterval(delay)
                    queuedItem.errorSummary = backupError.errorDescription
                }
            } else {
                try await transition(itemID: itemID) { queuedItem in
                    queuedItem.state = backupError.failClosedState
                    queuedItem.nextAttemptAt = nil
                    queuedItem.errorSummary = backupError.errorDescription
                }
            }
        } catch {
            // Persisting a failure must never trigger an upload retry in memory.
        }
    }

    private func retryDelay(for retryCount: Int) -> TimeInterval {
        let cappedBase = min(300, pow(2, Double(max(0, retryCount - 1))))
        return min(300, cappedBase + max(0, min(jitter(), cappedBase * 0.25)))
    }

    private func transition(
        itemID: UUID,
        _ change: (inout RemoteQueueItem) -> Void
    ) async throws {
        guard var updatedItem = items[itemID] else { return }
        change(&updatedItem)
        updatedItem.updatedAt = now()
        try await persistence.save(updatedItem)
        items[itemID] = updatedItem
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
