import Foundation
import Testing
@testable import BitMatch

struct RemoteBackupQueueTests {
    @Test func existingFinalObjectBecomesConflictWithoutUploading() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(objects: [fixture.item.remoteRelativePath: .init(byteCount: 10)])
        let queue = fixture.makeQueue(provider: provider)

        await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .conflict)
        #expect(await provider.uploadCallCount == 0)
    }

    @Test func interruptedUploadResumesOnlyWhenStoredAndServerOffsetsMatch() async throws {
        let fixture = try QueueFixture(uploadedByteCount: 4)
        let provider = FakeRemoteBackupProvider(objects: [fixture.item.temporaryRemoteRelativePath: .init(byteCount: 4)])
        let queue = fixture.makeQueue(provider: provider)

        await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await provider.uploadOffsets == [4])
        #expect(await queue.item(id: fixture.item.id)?.state == .uploadedUnverified)
    }

    @Test func mismatchedTemporaryOffsetPausesWithoutUploading() async throws {
        let fixture = try QueueFixture(uploadedByteCount: 4)
        let provider = FakeRemoteBackupProvider(objects: [fixture.item.temporaryRemoteRelativePath: .init(byteCount: 3)])
        let queue = fixture.makeQueue(provider: provider)

        await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.uploadCallCount == 0)
    }

    @Test func transientNetworkFailurePersistsRetryAndBackoff() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(uploadError: .networkUnavailable)
        let queue = fixture.makeQueue(provider: provider)

        await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        let stored = await fixture.persistence.queueItem(id: fixture.item.id)
        #expect(stored?.state == .retrying)
        #expect(stored?.retryCount == 1)
        #expect(stored?.nextAttemptAt != nil)
    }

    @Test(arguments: [
        RemoteBackupError.authenticationFailed,
        .hostKeyMismatch,
        .unsafePath,
        .permissionDenied
    ])
    func nonTransientProviderFailuresFailClosed(_ error: RemoteBackupError) async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(preflightError: error)
        let queue = fixture.makeQueue(provider: provider)

        await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.uploadCallCount == 0)
    }

    @Test func bookmarkFailurePausesBeforeProviderUse() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider, resolver: { _ in
            throw RemoteBackupError.bookmarkUnavailable
        })

        await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.preflightCallCount == 0)
    }
}

private struct QueueFixture {
    let profile: RemoteDestinationProfile
    let manifest: RemoteManifest
    let item: RemoteQueueItem
    let persistence: FakeRemoteBackupQueuePersistence

    init(uploadedByteCount: Int64 = 0) throws {
        let root = try RemoteRelativePath(components: ["BitMatch"])
        let package = try RemoteRelativePath(components: ["Jobs", "Job-001"])
        let file = try RemoteRelativePath(components: ["Jobs", "Job-001", "Card-001.mov"])
        let temporary = try RemoteRelativePath(components: ["Jobs", "Job-001", ".bitmatch-upload-001"])
        let profileID = UUID()
        let manifestEntry = RemoteManifestEntry(
            id: UUID(),
            relativePath: file,
            byteCount: 10,
            sha256: String(repeating: "a", count: 64)
        )

        profile = RemoteDestinationProfile(
            id: profileID,
            name: "Archive",
            host: "archive.example.test",
            port: 22,
            username: "photographer",
            root: root,
            verificationMode: .uploadOnly
        )
        manifest = try RemoteManifest(
            id: UUID(),
            jobID: UUID(),
            cardIngestID: UUID(),
            destinationProfileID: profileID,
            packageRelativePath: package,
            entries: [manifestEntry],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        item = RemoteQueueItem(
            id: UUID(),
            jobID: manifest.jobID,
            cardIngestID: manifest.cardIngestID,
            destinationProfileID: profileID,
            manifestID: manifest.id,
            manifestEntryID: manifestEntry.id,
            localArtifactBookmarkReference: "opaque-bookmark-reference",
            localArtifactRelativePath: file,
            remoteRelativePath: file,
            temporaryRemoteRelativePath: temporary,
            state: .queued,
            uploadedByteCount: uploadedByteCount,
            retryCount: 0,
            nextAttemptAt: nil,
            verificationEvidence: .none,
            errorSummary: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        persistence = FakeRemoteBackupQueuePersistence(
            profiles: [profile],
            manifests: [manifest],
            credential: RemoteCredential(password: "test-password")
        )
    }

    func makeQueue(
        provider: FakeRemoteBackupProvider,
        resolver: @escaping RemoteBackupLocalArtifactResolver = { _ in URL(fileURLWithPath: "/tmp/Card-001.mov") }
    ) -> RemoteBackupQueue {
        RemoteBackupQueue(
            persistence: persistence,
            providerFactory: { _, _ in provider },
            localArtifactResolver: resolver,
            now: { Date(timeIntervalSince1970: 100) },
            jitter: { 0 }
        )
    }
}

private actor FakeRemoteBackupQueuePersistence: RemoteBackupQueuePersistence {
    private var savedProfiles: [RemoteDestinationProfile]
    private var savedManifests: [RemoteManifest]
    private var savedItems: [UUID: RemoteQueueItem] = [:]
    private let savedCredential: RemoteCredential?

    init(profiles: [RemoteDestinationProfile], manifests: [RemoteManifest], credential: RemoteCredential?) {
        savedProfiles = profiles
        savedManifests = manifests
        savedCredential = credential
    }

    func profiles() async throws -> [RemoteDestinationProfile] { savedProfiles }
    func manifests() async throws -> [RemoteManifest] { savedManifests }
    func queueItems() async throws -> [RemoteQueueItem] { Array(savedItems.values) }
    func credential(for _: UUID) async throws -> RemoteCredential? { savedCredential }
    func save(_ item: RemoteQueueItem) async throws { savedItems[item.id] = item }
    func deleteQueueItem(id: UUID) async throws { savedItems[id] = nil }
    func queueItem(id: UUID) -> RemoteQueueItem? { savedItems[id] }
}

private actor FakeRemoteBackupProvider: RemoteBackupProvider {
    private var remoteObjects: [RemoteRelativePath: RemoteObject]
    private let capabilities: RemoteProviderCapabilities
    private let preflightError: RemoteBackupError?
    private let uploadError: RemoteBackupError?
    private(set) var uploadCallCount = 0
    private(set) var preflightCallCount = 0
    private(set) var uploadOffsets: [Int64] = []

    init(
        objects: [RemoteRelativePath: RemoteObject] = [:],
        capabilities: RemoteProviderCapabilities = .init(),
        preflightError: RemoteBackupError? = nil,
        uploadError: RemoteBackupError? = nil
    ) {
        remoteObjects = objects
        self.capabilities = capabilities
        self.preflightError = preflightError
        self.uploadError = uploadError
    }

    func preflight(profile _: RemoteDestinationProfile, credential _: RemoteCredential) async throws -> RemoteProviderCapabilities {
        preflightCallCount += 1
        if let preflightError { throw preflightError }
        return capabilities
    }

    func inspect(path: RemoteRelativePath) async throws -> RemoteObject? { remoteObjects[path] }
    func ensureDirectory(_: RemoteRelativePath) async throws {}

    func upload(
        local _: URL,
        toTemporary path: RemoteRelativePath,
        fromOffset: Int64,
        progress: @Sendable (Int64) async -> Void
    ) async throws {
        uploadCallCount += 1
        uploadOffsets.append(fromOffset)
        if let uploadError { throw uploadError }
        remoteObjects[path] = RemoteObject(byteCount: 10)
        await progress(10)
    }

    func promoteNoReplace(temporary: RemoteRelativePath, final: RemoteRelativePath) async throws {
        if remoteObjects[final] != nil { throw RemoteBackupError.conflict }
        remoteObjects[final] = remoteObjects.removeValue(forKey: temporary)
    }

    func verificationEvidence(for _: RemoteRelativePath, expectedSHA256 _: String) async throws -> RemoteVerificationEvidence {
        .sha256(String(repeating: "a", count: 64))
    }

    func close() async {}
}
