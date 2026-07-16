import Foundation
import Testing
@testable import BitMatch

struct RemoteBackupQueueTests {
    @Test func existingFinalObjectBecomesConflictWithoutUploading() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(objects: [fixture.item.remoteRelativePath: .init(byteCount: 10)])
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .conflict)
        #expect(await provider.uploadCallCount == 0)
    }

    @Test func ownedFinalAfterPromotionResumesVerificationInsteadOfConflicting() async throws {
        let fixture = try QueueFixture(verificationMode: .sha256)
        let provider = FakeRemoteBackupProvider(verificationErrors: [.networkUnavailable])
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .verifying)
        #expect(await provider.promoteCallCount == 1)

        let recoveredQueue = fixture.makeQueue(provider: provider, now: Date(timeIntervalSince1970: 200))
        try await recoveredQueue.restore()
        await recoveredQueue.run(fixture.item.id)

        #expect(await recoveredQueue.item(id: fixture.item.id)?.state == .verified)
        #expect(await provider.uploadCallCount == 1)
        #expect(await provider.promoteCallCount == 1)
    }

    @Test func interruptedUploadResumesOnlyWhenStoredAndServerOffsetsMatch() async throws {
        let fixture = try QueueFixture(uploadedByteCount: 4)
        let provider = FakeRemoteBackupProvider(objects: [fixture.item.temporaryRemoteRelativePath: .init(byteCount: 4)])
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await provider.uploadOffsets == [4])
        #expect(await queue.item(id: fixture.item.id)?.state == .uploadedUnverified)
    }

    @Test func mismatchedTemporaryOffsetPausesWithoutUploading() async throws {
        let fixture = try QueueFixture(uploadedByteCount: 4)
        let provider = FakeRemoteBackupProvider(objects: [fixture.item.temporaryRemoteRelativePath: .init(byteCount: 3)])
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.uploadCallCount == 0)
    }

    @Test func transientNetworkFailurePersistsRetryAndBackoff() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(uploadError: .networkUnavailable)
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
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

        try await queue.enqueue(fixture.item)
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

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.preflightCallCount == 0)
    }

    @Test func duplicateRunsShareOneUploadAndPromotion() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(blockUpload: true)
        let queue = fixture.makeQueue(provider: provider)
        try await queue.enqueue(fixture.item)

        let firstRun = Task { await queue.run(fixture.item.id) }
        await provider.waitForUploadStart()
        await queue.run(fixture.item.id)
        await provider.resumeUpload()
        await firstRun.value

        #expect(await provider.uploadCallCount == 1)
        #expect(await provider.promoteCallCount == 1)
    }

    @Test func cancellationPersistsAndRunningUploadCannotOverwriteIt() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(blockUpload: true)
        let queue = fixture.makeQueue(provider: provider)
        try await queue.enqueue(fixture.item)

        let running = Task { await queue.run(fixture.item.id) }
        await provider.waitForUploadStart()
        try await queue.cancel(fixture.item.id)
        await provider.resumeUpload()
        await running.value

        #expect(await queue.item(id: fixture.item.id)?.state == .cancelled)
        #expect(await fixture.persistence.queueItem(id: fixture.item.id)?.state == .cancelled)
        #expect(await provider.promoteCallCount == 0)
    }

    @Test(arguments: ["manifest", "entry", "profile"])
    func invalidPersistedLinkagePausesBeforeProviderUse(_ mismatch: String) async throws {
        let fixture = try QueueFixture(mismatch: mismatch)
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.preflightCallCount == 0)
    }

    @Test(arguments: ["deletedJob", "unownedCard"])
    func deletedOrUnownedJobCardPausesBeforeProviderUse(_ mismatch: String) async throws {
        let fixture = try QueueFixture(mismatch: mismatch)
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.preflightCallCount == 0)
    }

    @Test func invalidLinkageClearsPromotionIntentAndPausesBeforeProviderUse() async throws {
        let fixture = try QueueFixture(state: .verifying, mismatch: "deletedJob")
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.preflightCallCount == 0)
    }

    @Test(arguments: ["package", "final", "temporary"])
    func forgedRemotePathsPauseBeforeProviderUse(_ mismatch: String) async throws {
        let fixture = try QueueFixture(mismatch: mismatch)
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await provider.preflightCallCount == 0)
    }

    @Test func enqueueIsDurableBeforeItReturnsAndRestoreDoesNotOverwriteIt() async throws {
        let fixture = try QueueFixture()
        let queue = fixture.makeQueue(provider: FakeRemoteBackupProvider())

        try await queue.enqueue(fixture.item)
        try await queue.restore()

        #expect(await fixture.persistence.queueItem(id: fixture.item.id) == fixture.item)
        #expect(await queue.item(id: fixture.item.id) == fixture.item)
    }
}

private struct QueueFixture {
    let profile: RemoteDestinationProfile
    let manifest: RemoteManifest
    let item: RemoteQueueItem
    let persistence: FakeRemoteBackupQueuePersistence

    init(
        uploadedByteCount: Int64 = 0,
        verificationMode: RemoteVerificationMode = .uploadOnly,
        state: RemoteBackupState = .queued,
        mismatch: String? = nil
    ) throws {
        let root = try RemoteRelativePath(components: ["BitMatch"])
        let package = try RemoteRelativePath(components: ["Jobs", "Job-001"])
        let file = try RemoteRelativePath(components: ["Card-001.mov"])
        let profileID = UUID()
        let manifestJobID = UUID()
        let manifestCardID = UUID()
        let itemID = UUID()
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
            verificationMode: verificationMode
        )
        let manifestPackage = mismatch == "package"
            ? try RemoteRelativePath(components: ["Jobs", "Forged-Job"])
            : package
        manifest = try RemoteManifest(
            id: UUID(),
            jobID: manifestJobID,
            cardIngestID: manifestCardID,
            destinationProfileID: profileID,
            packageRelativePath: manifestPackage,
            entries: [manifestEntry],
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let final = try package.appending(path: file)
        let temporary = try package.appending(".bitmatch-upload-\(itemID.uuidString.lowercased())")
        let remotePath = mismatch == "final"
            ? try RemoteRelativePath(components: ["Jobs", "Job-001", "Other.mov"])
            : final
        let temporaryPath = mismatch == "temporary"
            ? try RemoteRelativePath(components: ["Jobs", "Job-001", ".bitmatch-upload-forged"])
            : temporary
        let card = Self.makeCard(id: manifestCardID)
        let jobCards = mismatch == "unownedCard" ? [Self.makeCard(id: UUID())] : [card]
        let jobs = mismatch == "deletedJob" ? [] : [Self.makeJob(id: manifestJobID, cardIngests: jobCards)]
        item = RemoteQueueItem(
            id: itemID,
            jobID: manifest.jobID,
            cardIngestID: manifest.cardIngestID,
            destinationProfileID: mismatch == "profile" ? UUID() : profileID,
            manifestID: mismatch == "manifest" ? UUID() : manifest.id,
            manifestEntryID: mismatch == "entry" ? UUID() : manifestEntry.id,
            localArtifactBookmarkReference: "opaque-bookmark-reference",
            localArtifactRelativePath: file,
            remoteRelativePath: remotePath,
            temporaryRemoteRelativePath: temporaryPath,
            state: state,
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
            jobs: jobs,
            credential: RemoteCredential(password: "test-password")
        )
    }

    private static func makeJob(id: UUID, cardIngests: [CardIngest]) -> PhotographerJob {
        PhotographerJob(
            id: id,
            eventDate: Date(timeIntervalSince1970: 0),
            clientName: "Client",
            jobName: "Job-001",
            eventType: .wedding,
            photographers: [],
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            cardIngests: cardIngests,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeCard(id: UUID) -> CardIngest {
        CardIngest(
            id: id,
            provenance: CardProvenance(
                photographerID: UUID(),
                photographerName: "Photographer",
                cameraName: "Camera",
                cardNumber: 1,
                preliminaryFingerprint: nil,
                confirmedFingerprint: nil
            ),
            sourceDisplayName: "Card-001",
            renderedRelativePath: "Jobs/Job-001",
            localState: .locallySafe,
            startedAt: nil,
            locallySafeAt: Date(timeIntervalSince1970: 0),
            fileCount: 1,
            totalBytes: 10
        )
    }

    func makeQueue(
        provider: FakeRemoteBackupProvider,
        resolver: @escaping RemoteBackupLocalArtifactResolver = { _ in
            RemoteBackupArtifactLease(url: URL(fileURLWithPath: "/tmp/Card-001.mov"), releaseAccess: {})
        },
        now: Date = Date(timeIntervalSince1970: 100)
    ) -> RemoteBackupQueue {
        RemoteBackupQueue(
            persistence: persistence,
            providerFactory: { _, _ in provider },
            localArtifactResolver: resolver,
            now: { now },
            jitter: { 0 }
        )
    }
}

private actor FakeRemoteBackupQueuePersistence: RemoteBackupQueuePersistence {
    private var savedProfiles: [RemoteDestinationProfile]
    private var savedManifests: [RemoteManifest]
    private var savedJobs: [PhotographerJob]
    private var savedItems: [UUID: RemoteQueueItem] = [:]
    private let savedCredential: RemoteCredential?

    init(
        profiles: [RemoteDestinationProfile],
        manifests: [RemoteManifest],
        jobs: [PhotographerJob],
        credential: RemoteCredential?
    ) {
        savedProfiles = profiles
        savedManifests = manifests
        savedJobs = jobs
        savedCredential = credential
    }

    func profiles() async throws -> [RemoteDestinationProfile] { savedProfiles }
    func manifests() async throws -> [RemoteManifest] { savedManifests }
    func jobs() async throws -> [PhotographerJob] { savedJobs }
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
    private var verificationErrors: [RemoteBackupError]
    private let blockUpload: Bool
    private var uploadStartedContinuation: CheckedContinuation<Void, Never>?
    private var uploadContinuation: CheckedContinuation<Void, Never>?
    private(set) var uploadCallCount = 0
    private(set) var preflightCallCount = 0
    private(set) var uploadOffsets: [Int64] = []
    private(set) var promoteCallCount = 0

    init(
        objects: [RemoteRelativePath: RemoteObject] = [:],
        capabilities: RemoteProviderCapabilities = .init(),
        preflightError: RemoteBackupError? = nil,
        uploadError: RemoteBackupError? = nil,
        verificationErrors: [RemoteBackupError] = [],
        blockUpload: Bool = false
    ) {
        remoteObjects = objects
        self.capabilities = capabilities
        self.preflightError = preflightError
        self.uploadError = uploadError
        self.verificationErrors = verificationErrors
        self.blockUpload = blockUpload
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
        uploadStartedContinuation?.resume()
        uploadStartedContinuation = nil
        if blockUpload {
            await withCheckedContinuation { uploadContinuation = $0 }
        }
        if let uploadError { throw uploadError }
        remoteObjects[path] = RemoteObject(byteCount: 10)
        await progress(10)
    }

    func promoteNoReplace(temporary: RemoteRelativePath, final: RemoteRelativePath) async throws {
        promoteCallCount += 1
        if remoteObjects[final] != nil { throw RemoteBackupError.conflict }
        remoteObjects[final] = remoteObjects.removeValue(forKey: temporary)
    }

    func verificationEvidence(for _: RemoteRelativePath, expectedSHA256 _: String) async throws -> RemoteVerificationEvidence {
        if !verificationErrors.isEmpty {
            throw verificationErrors.removeFirst()
        }
        return .sha256(String(repeating: "a", count: 64))
    }

    func close() async {}

    func waitForUploadStart() async {
        if uploadCallCount > 0 { return }
        await withCheckedContinuation { uploadStartedContinuation = $0 }
    }

    func resumeUpload() {
        uploadContinuation?.resume()
        uploadContinuation = nil
    }
}
