import Foundation
import Testing
@testable import BitMatch

/// The rules `AppCoordinator` enforced for the Mac, checked against
/// `SharedAppCoordinator` alone, which every platform will run on
/// (thesis step 3). Each plant names the one-line production change that
/// should make the test fail.
@MainActor
@Suite(.serialized)
struct SharedCoordinatorMacParityTests {

    /// A card prepared before the coordinator exists (the Mac restores one
    /// from Core Data) must still be startable afterwards.
    /// Plant: in `SharedAppCoordinator.setupBindings`, delete the
    /// `.dropFirst()` before the `sourceDidChange` sink.
    @Test func preparedCardSurvivesCoordinatorInit() async throws {
        let folders = try CoordinatorFolders()
        defer { folders.cleanup() }
        let jobs = PhotographerJobViewModel(store: InMemoryPhotographerJobStore())
        jobs.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: Date(timeIntervalSince1970: 100))
        try jobs.prepareCard(
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            sourceURL: folders.source,
            setupSignature: PhotographerSetupSignature(
                clientName: "Smith", jobName: "Smith Wedding", eventDate: Date(timeIntervalSince1970: 100),
                photographerName: "Mike", cameraName: "Sony A7 IV", cardNumber: 1, recipe: .wedding
            ),
            analysis: CardAnalysis(fingerprint: "preliminary", fileCount: 1, totalBytes: 4,
                                   companionGroups: [], sourcePaths: [folders.source.appendingPathComponent("A.ARW").path])
        )

        let coordinator = SharedAppCoordinator(
            platformManager: RecordingPlatformManager(fileOperations: RecordingFileOperations()),
            transferJournal: LocalTransferJournal(fileURL: folders.journalURL),
            photographerJobViewModel: jobs
        )
        // Let every launch-time source event arrive.
        for _ in 0..<5 { await Task.yield() }
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(coordinator.photographerJobViewModel === jobs)
        #expect(jobs.startPresentation(
            preflightReady: true,
            sourceURL: folders.source,
            destinationCount: 2
        ).canStart)
    }

    /// Plant: in `PhotographerJobViewModel.beginIngest`, drop the
    /// `guard presentation.canStart` check.
    @Test func twoCopyJobWithOneBackupIsRefused() async throws {
        let fixture = try await SharedProjectFixture.make()
        defer { fixture.folders.cleanup() }
        fixture.coordinator.destinationURLs = [fixture.folders.primary]

        let started = await fixture.coordinator.startProjectOperation()

        #expect(!started)
        #expect(fixture.cardState == .notStarted)
        #expect(await fixture.operations.starts.isEmpty)
    }

    /// Plant: in `PhotographerJobViewModel.startPresentation`, make
    /// `sourceMatches` always true.
    @Test func changedSourceIsRefused() async throws {
        let fixture = try await SharedProjectFixture.make()
        defer { fixture.folders.cleanup() }
        fixture.coordinator.sourceURL = fixture.folders.secondary

        let started = await fixture.coordinator.startProjectOperation()

        #expect(!started)
        #expect(fixture.cardState == .notStarted)
        #expect(await fixture.operations.starts.isEmpty)
    }

    /// Plant: in `SharedAppCoordinator.cancelOperation`, delete
    /// `updateProjectLifecycle(for: .cancelled)`.
    @Test func cancellingCancelsThePreparedCard() async throws {
        let fixture = try await SharedProjectFixture.make(blocked: true)
        let start = Task { await fixture.coordinator.startProjectOperation() }
        #expect(await waitUntil(timeout: .seconds(5)) { await fixture.operations.starts.count == 1 })

        fixture.coordinator.cancelOperation()

        #expect(fixture.cardState == .cancelled)
        _ = await start.value
        await fixture.cleanup()
        // Late engine events must not bring the card back.
        #expect(fixture.cardState == .cancelled)
    }

    /// Plant: in `SharedAppCoordinator.executeOperation`'s journal `catch`,
    /// delete `updateProjectLifecycle(for: .failed)`.
    @Test func failedStartEndsTheCardInIssues() async throws {
        let fixture = try await SharedProjectFixture.make(corruptJournal: true)
        defer { fixture.folders.cleanup() }

        _ = await fixture.coordinator.startProjectOperation()

        #expect(fixture.cardState == .issues)
        #expect(await fixture.operations.starts.isEmpty)
        #expect(!fixture.coordinator.isOperationInProgress)
    }

    /// Plant: in `SharedAppCoordinator.updateProjectLifecycle`, delete
    /// `if !info.success { photographerJobViewModel.operationFailed() }`.
    @Test func unverifiedFinishEndsTheCardInIssues() async throws {
        let fixture = try await SharedProjectFixture.make()
        defer { fixture.folders.cleanup() }

        let started = await fixture.coordinator.startProjectOperation()
        await fixture.waitUntilIdle()

        #expect(started)
        #expect(await fixture.operations.starts.count == 1)
        #expect(fixture.cardState == .issues)
    }

    /// Plant: in `SharedAppCoordinator.compareFolders`, call
    /// `photographerJobViewModel.updateProgressStage(.copying)` when it sets
    /// `operationState = .inProgress`.
    @Test func compareNeverTouchesThePreparedCard() async throws {
        let fixture = try await SharedProjectFixture.make()
        defer { fixture.folders.cleanup() }
        let savesBefore = fixture.store.saveCount
        fixture.coordinator.switchMode(to: .compareFolders)
        fixture.coordinator.leftURL = fixture.folders.primary
        fixture.coordinator.rightURL = fixture.folders.secondary

        await fixture.coordinator.compareFolders()

        #expect(fixture.coordinator.lastCompareEnd == .completed)
        #expect(fixture.cardState == .notStarted)
        #expect(fixture.store.saveCount == savesBefore)
    }

    /// The Mac refused to start while the source was still being scanned;
    /// now every platform does.
    /// Plant: in `OperationReadinessAssessment.assess`, set
    /// `isReady: issues.isEmpty`.
    @Test func startIsRefusedWhileTheSourceIsAnalysing() async throws {
        let fixture = try await SharedProjectFixture.make(prepareCard: false)
        defer { fixture.folders.cleanup() }
        let other = fixture.folders.root.appendingPathComponent("other-card", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        // No suspension between choosing the source and asking: the scan
        // cannot have finished.
        fixture.coordinator.sourceURL = other

        #expect(!fixture.coordinator.canStartOperation)
        #expect(fixture.coordinator.operationReadinessAssessment.isAnalysing)
        // Once the scan finishes, the same selection is ready.
        #expect(await waitUntil(timeout: .seconds(5)) { fixture.coordinator.canStartOperation })
    }

    /// The Mac applied the job's folder recipe to the run; shared does not
    /// yet, so iPad and iPhone project cards run without it (Task 8).
    @Test func projectRunUsesTheJobsFolderRecipe() async throws {
        let fixture = try await SharedProjectFixture.make()
        defer { fixture.folders.cleanup() }
        let recipe = try #require(fixture.jobs.renderedRecipe)

        _ = await fixture.coordinator.startProjectOperation()
        await fixture.waitUntilIdle()

        let start = try #require(await fixture.operations.starts.first)
        withKnownIssue("startProjectOperation does not apply the recipe until Task 8") {
            #expect(start.destinationPathComponents == recipe.components)
        }
    }
}
