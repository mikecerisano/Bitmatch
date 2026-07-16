import Foundation

/// Stores the opaque reference in Core Data while keeping bookmark bytes out
/// of every Codable remote-backup payload.
protocol RemoteArtifactBookmarkStore {
    func save(_ data: Data, for reference: String) throws
    func data(for reference: String) throws -> Data?
    func remove(reference: String) throws
}

struct KeychainRemoteArtifactBookmarkStore: RemoteArtifactBookmarkStore {
    func save(_ data: Data, for reference: String) throws {
        guard KeychainHelper.save(data, forKey: reference) else {
            throw RemoteBackupError.bookmarkUnavailable
        }
    }

    func data(for reference: String) throws -> Data? {
        KeychainHelper.load(forKey: reference)
    }

    func remove(reference: String) throws {
        guard KeychainHelper.delete(forKey: reference) else {
            throw RemoteBackupError.bookmarkUnavailable
        }
    }
}

/// The bridge between immutable local transfer evidence and the persistent
/// remote queue. It never reads the source card: package roots are derived
/// only from final `ResultRow.destinationPath` values.
@MainActor
final class RemoteBackupCoordinator {
    typealias BookmarkMaker = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> URL
    typealias FileSize = (URL) throws -> Int64
    typealias SHA256 = (URL) async throws -> String

    private let store: any PhotographerJobStore
    private let bookmarkStore: any RemoteArtifactBookmarkStore
    private let makeBookmark: BookmarkMaker
    private let resolveBookmark: BookmarkResolver
    private let fileSize: FileSize
    private let sha256: SHA256
    private let now: () -> Date

    init(
        store: any PhotographerJobStore,
        bookmarkStore: any RemoteArtifactBookmarkStore = KeychainRemoteArtifactBookmarkStore(),
        makeBookmark: @escaping BookmarkMaker = makeSecurityScopedBookmark,
        resolveBookmark: @escaping BookmarkResolver = resolveSecurityScopedBookmark,
        fileSize: @escaping FileSize = remoteArtifactFileSize,
        sha256: @escaping SHA256 = remoteArtifactSHA256,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.bookmarkStore = bookmarkStore
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
        self.fileSize = fileSize
        self.sha256 = sha256
        self.now = now
    }

    @discardableResult
    func selectRemoteProfile(_ profileID: UUID?, for jobID: UUID) throws -> PhotographerJob {
        guard var job = try store.jobs().first(where: { $0.id == jobID }) else {
            throw RemoteBackupError.manifestUnavailable
        }
        if let profileID {
            guard try store.profiles().contains(where: { $0.id == profileID }) else {
                throw RemoteBackupError.missingProfile
            }
            job.remoteBackupConfiguration = RemoteBackupConfiguration(
                isEnabled: true,
                destinationProfileID: profileID
            )
        } else {
            job.remoteBackupConfiguration = RemoteBackupConfiguration()
        }
        job.updatedAt = now()
        try store.save(job)
        return job
    }

    /// Persists an immutable remote manifest and one durable queue item per
    /// verified local file. This is intentionally synchronous: a queue worker
    /// can only see an item after its manifest and package bookmark exist.
    func queueRemoteBackup(
        for cardIngestID: UUID,
        in jobID: UUID,
        results: [ResultRow]
    ) throws -> [RemoteQueueItem] {
        guard let job = try store.jobs().first(where: { $0.id == jobID }),
              let card = job.cardIngests.first(where: { $0.id == cardIngestID }),
              card.localState == .locallySafe,
              card.locallySafeAt != nil,
              card.verifiedDestinationCount >= job.requiredLocalCopyCount,
              !(card.provenance.confirmedFingerprint ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteBackupError.localArtifactNotVerified
        }
        guard let configuration = job.remoteBackupConfiguration,
              configuration.isEnabled,
              let profileID = configuration.destinationProfileID,
              try store.profiles().contains(where: { $0.id == profileID }) else {
            throw RemoteBackupError.missingProfile
        }

        let artifacts = try verifiedArtifacts(for: card, requiredDestinationCount: job.requiredLocalCopyCount, results: results)
        guard let selectedArtifact = artifacts.sorted(by: { $0.packageRoot.path < $1.packageRoot.path }).first else {
            throw RemoteBackupError.localArtifactNotVerified
        }

        let cardPackagePath = try remotePath(from: card.renderedRelativePath)
        let packageRelativePath: RemoteRelativePath
        if let destinationPath = configuration.destinationPath {
            packageRelativePath = try destinationPath.appending(path: cardPackagePath)
        } else {
            packageRelativePath = cardPackagePath
        }
        let manifestID = UUID()
        let bookmarkReference = "remote-artifact.\(manifestID.uuidString.lowercased())"
        let manifestEntries = selectedArtifact.entries.map { artifact in
            RemoteManifestEntry(
                id: UUID(),
                relativePath: artifact.relativePath,
                byteCount: artifact.byteCount,
                sha256: artifact.sha256
            )
        }
        let manifest = try RemoteManifest(
            id: manifestID,
            jobID: jobID,
            cardIngestID: cardIngestID,
            destinationProfileID: profileID,
            packageRelativePath: packageRelativePath,
            entries: manifestEntries,
            createdAt: now()
        )

        // The bookmark is deliberately made from the verified destination
        // package root, never from ResultRow.path or the camera-card source.
        try bookmarkStore.save(try makeBookmark(selectedArtifact.packageRoot), for: bookmarkReference)
        do {
            try store.save(manifest)
            let items = try manifest.entries.map { entry in
                let itemID = UUID()
                let final = try manifest.packageRelativePath.appending(path: entry.relativePath)
                let temporary = try temporaryPath(final: final, itemID: itemID)
                let item = RemoteQueueItem(
                    id: itemID,
                    jobID: jobID,
                    cardIngestID: cardIngestID,
                    destinationProfileID: profileID,
                    manifestID: manifest.id,
                    manifestEntryID: entry.id,
                    localArtifactBookmarkReference: bookmarkReference,
                    localArtifactRelativePath: entry.relativePath,
                    remoteRelativePath: final,
                    temporaryRemoteRelativePath: temporary,
                    state: .queued,
                    uploadedByteCount: 0,
                    retryCount: 0,
                    nextAttemptAt: nil,
                    verificationEvidence: .none,
                    errorSummary: nil,
                    createdAt: now(),
                    updatedAt: now()
                )
                try store.save(item)
                return item
            }
            return items
        } catch {
            try? store.deleteManifest(id: manifestID)
            try? bookmarkStore.remove(reference: bookmarkReference)
            throw error
        }
    }

    func pauseRemoteBackup(for cardIngestID: UUID, in jobID: UUID) throws -> [RemoteQueueItem] {
        try updateQueueItems(for: cardIngestID, in: jobID) { item in
            guard !item.state.isTerminal else { return }
            item.state = .paused
            item.nextAttemptAt = nil
            item.errorSummary = nil
        }
    }

    func retryRemoteBackup(for cardIngestID: UUID, in jobID: UUID) throws -> [RemoteQueueItem] {
        try updateQueueItems(for: cardIngestID, in: jobID) { item in
            guard item.state == .paused || item.state == .retrying else { return }
            item.state = .queued
            item.nextAttemptAt = nil
            item.errorSummary = nil
        }
    }

    /// Called by `RemoteBackupQueue` immediately before it hands a URL to a
    /// provider. It resolves the persisted package bookmark and proves that
    /// the requested file is still contained, equal-sized, and SHA-256-equal.
    func resolveLocalArtifact(for item: RemoteQueueItem) async throws -> URL {
        guard let manifest = try store.manifests().first(where: { $0.id == item.manifestID }),
              manifest.jobID == item.jobID,
              manifest.cardIngestID == item.cardIngestID,
              manifest.destinationProfileID == item.destinationProfileID,
              let entry = manifest.entries.first(where: { $0.id == item.manifestEntryID }),
              entry.relativePath == item.localArtifactRelativePath,
              let bookmark = try bookmarkStore.data(for: item.localArtifactBookmarkReference) else {
            throw RemoteBackupError.bookmarkUnavailable
        }

        let root: URL
        do {
            root = try resolveBookmark(bookmark).standardizedFileURL.resolvingSymlinksInPath()
        } catch {
            throw RemoteBackupError.bookmarkUnavailable
        }
        let file = root.appendingPathComponent(entry.relativePath.description, isDirectory: false)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard contains(file, in: root),
              (try? fileSize(file)) == entry.byteCount,
              let digest = try? await sha256(file),
              digest.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
            throw RemoteBackupError.localArtifactNotVerified
        }
        return file
    }

    private func updateQueueItems(
        for cardIngestID: UUID,
        in jobID: UUID,
        change: (inout RemoteQueueItem) -> Void
    ) throws -> [RemoteQueueItem] {
        guard try store.jobs().contains(where: { job in
            job.id == jobID && job.cardIngests.contains(where: { $0.id == cardIngestID })
        }) else {
            throw RemoteBackupError.manifestUnavailable
        }
        let matching = try store.queueItems().filter {
            $0.jobID == jobID && $0.cardIngestID == cardIngestID
        }
        var updated: [RemoteQueueItem] = []
        for var item in matching {
            let original = item
            change(&item)
            guard item != original else { continue }
            item.updatedAt = now()
            try store.save(item)
            updated.append(item)
        }
        return updated
    }

    private struct VerifiedArtifact {
        struct Entry {
            let relativePath: RemoteRelativePath
            let byteCount: Int64
            let sha256: String
        }

        let packageRoot: URL
        let entries: [Entry]
    }

    private func verifiedArtifacts(
        for card: CardIngest,
        requiredDestinationCount: Int,
        results: [ResultRow]
    ) throws -> [VerifiedArtifact] {
        let packageComponents = try remotePath(from: card.renderedRelativePath).components
        let verifiedRows = results.filter { row in
            row.isSuccessStatus && row.size >= 0 && validSHA256(row.checksum)
        }
        guard !verifiedRows.isEmpty, verifiedRows.count == results.count else {
            throw RemoteBackupError.localArtifactNotVerified
        }

        let grouped = Dictionary(grouping: verifiedRows.compactMap { row -> (URL, VerifiedArtifact.Entry)? in
            guard let destinationPath = nonblank(row.destinationPath), destinationPath.hasPrefix("/") else {
                return nil
            }
            let destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
            let components = destination.pathComponents
            guard let start = components.firstSubsequenceIndex(of: packageComponents) else { return nil }
            let end = start + packageComponents.count
            guard end < components.count else { return nil }
            let root = URL(fileURLWithPath: NSString.path(withComponents: Array(components[..<end])))
            let entryComponents = Array(components[end...])
            guard let relativePath = try? RemoteRelativePath(components: entryComponents),
                  let checksum = row.checksum else { return nil }
            return (root, .init(relativePath: relativePath, byteCount: row.size, sha256: checksum))
        }, by: { $0.0.standardizedFileURL.path })

        guard grouped.count >= requiredDestinationCount,
              grouped.values.reduce(0, { $0 + $1.count }) == verifiedRows.count else {
            throw RemoteBackupError.localArtifactNotVerified
        }
        let expectedCount = card.fileCount
        let artifacts = try grouped.map { rootPath, pairs -> VerifiedArtifact in
            let entries = pairs.map(\.1).sorted { $0.relativePath.description < $1.relativePath.description }
            guard entries.count == expectedCount,
                  Set(entries.map { $0.relativePath.portableComparisonKey }).count == entries.count else {
                throw RemoteBackupError.localArtifactNotVerified
            }
            return VerifiedArtifact(packageRoot: URL(fileURLWithPath: rootPath), entries: entries)
        }
        guard checksumEvidenceAgrees(artifacts) else {
            throw RemoteBackupError.localArtifactNotVerified
        }
        return artifacts
    }

    private func checksumEvidenceAgrees(_ artifacts: [VerifiedArtifact]) -> Bool {
        guard let first = artifacts.first else { return false }
        let baseline = Dictionary(uniqueKeysWithValues: first.entries.map { ($0.relativePath, $0.sha256.lowercased()) })
        return artifacts.allSatisfy { artifact in
            artifact.entries.count == baseline.count && artifact.entries.allSatisfy {
                baseline[$0.relativePath] == $0.sha256.lowercased()
            }
        }
    }

    private func remotePath(from path: String) throws -> RemoteRelativePath {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return try RemoteRelativePath(components: components)
    }

    private func temporaryPath(final: RemoteRelativePath, itemID: UUID) throws -> RemoteRelativePath {
        let parent = try RemoteRelativePath(components: Array(final.components.dropLast()))
        return try parent.appending(".bitmatch-upload-\(itemID.uuidString.lowercased())")
    }

    private func validSHA256(_ checksum: String?) -> Bool {
        guard let checksum, checksum.utf8.count == 64 else { return false }
        return checksum.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private func nonblank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func contains(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let urlPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return urlPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

}

private func makeSecurityScopedBookmark(for url: URL) throws -> Data {
    #if os(macOS)
    return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    #else
    return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    #endif
}

private func resolveSecurityScopedBookmark(_ data: Data) throws -> URL {
    var stale = false
    #if os(macOS)
    let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
    )
    #else
    let url = try URL(
        resolvingBookmarkData: data,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
    )
    #endif
    guard !stale else { throw RemoteBackupError.bookmarkUnavailable }
    return url
}

private func remoteArtifactFileSize(_ url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let size = values.fileSize else {
        throw RemoteBackupError.localArtifactNotVerified
    }
    return Int64(size)
}

private func remoteArtifactSHA256(_ url: URL) async throws -> String {
    try await SharedChecksumService.shared.generateChecksum(for: url, type: .sha256, useCache: false)
}

private extension RemoteBackupState {
    var isTerminal: Bool {
        switch self {
        case .uploadedUnverified, .verified, .failed, .cancelled, .conflict:
            true
        case .queued, .uploading, .retrying, .paused, .verifying:
            false
        }
    }
}

private extension Array where Element: Equatable {
    func firstSubsequenceIndex(of subsequence: [Element]) -> Int? {
        guard !subsequence.isEmpty, subsequence.count <= count else { return nil }
        for start in 0...(count - subsequence.count) where Array(self[start..<(start + subsequence.count)]) == subsequence {
            return start
        }
        return nil
    }
}
