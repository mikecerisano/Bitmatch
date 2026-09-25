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
    /// shared does not yet (Task 6b).
    @Test func startIsRefusedWhileTheSourceIsAnalysing() async throws {
        let fixture = try await SharedProjectFixture.make(prepareCard: false)
        defer { fixture.folders.cleanup() }
        let other = fixture.folders.root.appendingPathComponent("other-card", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        // No suspension between choosing the source and asking: the scan
        // cannot have finished.
        fixture.coordinator.sourceURL = other

        withKnownIssue("Readiness ignores an unfinished source scan until Task 6b") {
            #expect(!fixture.coordinator.canStartOperation)
        }
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
