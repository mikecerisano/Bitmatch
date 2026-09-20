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

    @Test func restoredPersistedWorkIsRunnableOnStartup() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider()
        let firstQueue = fixture.makeQueue(provider: provider)
        try await firstQueue.enqueue(fixture.item)

        let restartedQueue = fixture.makeQueue(provider: provider)
        try await restartedQueue.restore()

        #expect(await restartedQueue.runnableIDs() == [fixture.item.id])
        #expect(await restartedQueue.itemsForCardIngest(fixture.item.cardIngestID).map(\.id) == [fixture.item.id])
    }

    @Test @MainActor func appCoordinatorDrainsDueWorkAndRefreshesBackgroundSummary() async throws {
        let fixture = try QueueFixture()
        let store = InMemoryPhotographerJobStore()
        try store.save(fixture.job)
        try store.save(fixture.manifest)
        let activeJob = PhotographerJob(
            id: UUID(),
            eventDate: fixture.job.eventDate,
            clientName: "Active Client",
            jobName: "Active Job",
            eventType: fixture.job.eventType,
            photographers: [],
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            cardIngests: [],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.save(activeJob)
        let viewModel = PhotographerJobViewModel(store: store, now: { Date(timeIntervalSince1970: 200) })
        #expect(viewModel.activeJob?.id == activeJob.id)

        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)
        let coordinator = AppCoordinator(
            photographerJobViewModel: viewModel,
            remoteBackupQueue: queue,
            startRemoteScheduler: false
        )
        try await queue.enqueue(fixture.item)

        await coordinator.runDueRemoteBackups()

        #expect(await provider.uploadCallCount == 1)
        let savedBackground = try #require(store.storedJobs.first { $0.id == fixture.job.id })
        let savedCard = try #require(savedBackground.cardIngests.first)
        #expect(savedCard.remoteBackupSummaries[fixture.profile.id]?.state == .uploadedUnverified)
        #expect(coordinator.photographerJobViewModel.activeJob?.id == activeJob.id)
    }

    @Test func deferredBackoffWaitsForNextAttemptThenRunsAgain() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(uploadError: .networkUnavailable)
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(await queue.runnableIDs().isEmpty)
        let deferred = try #require(await queue.earliestDeferredAttempt())

        let laterQueue = fixture.makeQueue(provider: provider, now: deferred.addingTimeInterval(1))
        try await laterQueue.restore()
        #expect(await laterQueue.runnableIDs() == [fixture.item.id])
        await laterQueue.run(fixture.item.id)
        #expect(await provider.uploadCallCount == 2)
        #expect(await laterQueue.item(id: fixture.item.id)?.retryCount == 2)
    }

    @Test func transientFailuresExhaustToFailedWithManualRetryPath() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(uploadError: .networkUnavailable)
        try await fixture.makeQueue(provider: provider).enqueue(fixture.item)

        var lastQueue: RemoteBackupQueue?
        for attempt in 0 ..< 9 {
            let next = fixture.makeQueue(provider: provider, now: Date(timeIntervalSince1970: 100 + Double(attempt) * 10_000))
            try await next.restore()
            await next.run(fixture.item.id)
            lastQueue = next
        }
        let queue = try #require(lastQueue)

        #expect(await provider.uploadCallCount == 9)
        let exhausted = await queue.item(id: fixture.item.id)
        #expect(exhausted?.state == .failed)
        #expect(exhausted?.retryCount == RemoteBackupQueue.maxRetryCount + 1)
        #expect(exhausted?.nextAttemptAt == nil)
        #expect(exhausted?.errorSummary?.contains("Gave up after \(RemoteBackupQueue.maxRetryCount) attempts") == true)
        #expect(await queue.runnableIDs().isEmpty)

        try await queue.retry(fixture.item.id)
        let retried = await queue.item(id: fixture.item.id)
        #expect(retried?.state == .queued)
        #expect(retried?.retryCount == 0)
        #expect(await queue.runnableIDs() == [fixture.item.id])
    }

    @Test func retryExhaustionDuringVerificationRetainsPromotionIntent() async throws {
        let fixture = try QueueFixture(verificationMode: .sha256)
        let provider = FakeRemoteBackupProvider(
            verificationErrors: Array(repeating: .networkUnavailable, count: RemoteBackupQueue.maxRetryCount + 1)
        )
        try await fixture.makeQueue(provider: provider).enqueue(fixture.item)

        var lastQueue: RemoteBackupQueue?
        for attempt in 0 ... RemoteBackupQueue.maxRetryCount {
            let next = fixture.makeQueue(
                provider: provider,
                now: Date(timeIntervalSince1970: 100 + Double(attempt) * 10_000)
            )
            try await next.restore()
            await next.run(fixture.item.id)
            lastQueue = next
        }
        let queue = try #require(lastQueue)
        let exhausted = try #require(await queue.item(id: fixture.item.id))
        #expect(exhausted.state == .failed)
        #expect(exhausted.promotionIntent)

        try await queue.retry(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verifying)
        await queue.run(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verified)
    }

    @Test func pauseStopsSchedulerPickupUntilRetry() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        try await queue.pause(fixture.item.id)

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await queue.runnableIDs().isEmpty)
        await queue.run(fixture.item.id)
        #expect(await provider.uploadCallCount == 0)
        let stored = await fixture.persistence.queueItem(id: fixture.item.id)
        #expect(stored?.state == .paused)

        try await queue.retry(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .queued)
        await queue.run(fixture.item.id)
        #expect(await provider.uploadCallCount == 1)
    }

    @Test func cancelLeavesVerifiedWorkAlone() async throws {
        let fixture = try QueueFixture(verificationMode: .sha256)
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verified)

        try await queue.cancel(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verified)
    }

    @Test func retryLeavesVerifiedWorkAlone() async throws {
        let fixture = try QueueFixture(verificationMode: .sha256)
        let provider = FakeRemoteBackupProvider()
        let queue = fixture.makeQueue(provider: provider)

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)
        try await queue.retry(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verified)
        #expect(await queue.runnableIDs().isEmpty)
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

    @Test func bookmarkFailureDoesNotConstructProvider() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider()
        let factoryCalls = QueueFactoryCallCounter()
        let queue = RemoteBackupQueue(
            persistence: fixture.persistence,
            providerFactory: { _, _ in
                factoryCalls.record()
                return provider
            },
            localArtifactResolver: { _ in throw RemoteBackupError.localArtifactNotVerified },
            now: { Date(timeIntervalSince1970: 100) },
            jitter: { 0 }
        )

        try await queue.enqueue(fixture.item)
        await queue.run(fixture.item.id)

        #expect(factoryCalls.count == 0)
        #expect(await provider.preflightCallCount == 0)
        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
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

    @Test func pausingDuringPromotionRetainsIntentForSafeRetry() async throws {
        let fixture = try QueueFixture(verificationMode: .sha256)
        let provider = FakeRemoteBackupProvider(blockPromotion: true)
        let queue = fixture.makeQueue(provider: provider)
        try await queue.enqueue(fixture.item)

        let running = Task { await queue.run(fixture.item.id) }
        await provider.waitForPromotionStart()
        try await queue.pause(fixture.item.id)
        await provider.resumePromotion()
        await running.value

        let paused = try #require(await queue.item(id: fixture.item.id))
        #expect(paused.state == .paused)
        #expect(paused.promotionIntent)
        #expect(await provider.promoteCallCount == 1)

        try await queue.retry(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verifying)
        await queue.run(fixture.item.id)
        #expect(await queue.item(id: fixture.item.id)?.state == .verified)
        #expect(await provider.promoteCallCount == 1)
    }

    @Test func staleProviderErrorCannotReplacePausedState() async throws {
        let fixture = try QueueFixture()
        let provider = FakeRemoteBackupProvider(uploadError: .networkUnavailable, blockUpload: true)
        let queue = fixture.makeQueue(provider: provider)
        try await queue.enqueue(fixture.item)

        let running = Task { await queue.run(fixture.item.id) }
        await provider.waitForUploadStart()
        try await queue.pause(fixture.item.id)
        await provider.resumeUpload()
        await running.value

        #expect(await queue.item(id: fixture.item.id)?.state == .paused)
        #expect(await queue.item(id: fixture.item.id)?.nextAttemptAt == nil)
        #expect(await fixture.persistence.queueItem(id: fixture.item.id)?.state == .paused)
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

private final class QueueFactoryCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}

private struct QueueFixture {
    let profile: RemoteDestinationProfile
    let manifest: RemoteManifest
    let item: RemoteQueueItem
    let job: PhotographerJob
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
        let canonicalJob = Self.makeJob(id: manifestJobID, cardIngests: [card])
        job = canonicalJob
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
    private let blockPromotion: Bool
    private var uploadStartedContinuation: CheckedContinuation<Void, Never>?
    private var uploadContinuation: CheckedContinuation<Void, Never>?
    private var promotionStartedContinuation: CheckedContinuation<Void, Never>?
    private var promotionContinuation: CheckedContinuation<Void, Never>?
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
        blockUpload: Bool = false,
        blockPromotion: Bool = false
    ) {
        remoteObjects = objects
        self.capabilities = capabilities
        self.preflightError = preflightError
        self.uploadError = uploadError
        self.verificationErrors = verificationErrors
        self.blockUpload = blockUpload
        self.blockPromotion = blockPromotion
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
        promotionStartedContinuation?.resume()
        promotionStartedContinuation = nil
        if blockPromotion {
            await withCheckedContinuation { promotionContinuation = $0 }
        }
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

    func waitForPromotionStart() async {
        if promoteCallCount > 0 { return }
        await withCheckedContinuation { promotionStartedContinuation = $0 }
    }

    func resumePromotion() {
        promotionContinuation?.resume()
        promotionContinuation = nil
    }
}
