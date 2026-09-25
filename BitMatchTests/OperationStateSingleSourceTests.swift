// OperationStateSingleSourceTests.swift
// Thesis step 2 (Promise 2): an operation's state lives in one place. The
// verdict the screen shows (`SharedAppCoordinator.operationState`) and the
// pause/resume state (`OperationStateService.currentState`) used to be two
// copies that could disagree.
import Foundation
import Testing
@testable import BitMatch

#if os(macOS)
@MainActor
struct OperationStateSingleSourceTests {

    private func makeCoordinator() -> SharedAppCoordinator {
        SharedAppCoordinator(platformManager: MacOSPlatformManager.shared)
    }

    private func start(_ service: OperationStateService, id: UUID = UUID()) -> UUID {
        service.startOperation(
            id: id,
            sourceURL: URL(fileURLWithPath: "/tmp/card"),
            destinationURLs: [URL(fileURLWithPath: "/tmp/backup")],
            totalFiles: 1,
            totalBytes: 1
        )
        return id
    }

    /// Fails if `SharedAppCoordinator.operationState` goes back to being
    /// its own stored property.
    @Test func coordinatorAndStateServiceCannotDisagree() {
        let coordinator = makeCoordinator()
        _ = start(coordinator.stateService)
        #expect(coordinator.operationState == .inProgress)

        coordinator.operationState = .verifying
        #expect(coordinator.stateService.currentState == .verifying)
    }

    /// A transfer that finishes while paused (for example, an automatic
    /// pause racing the last file) must not stay "paused" forever.
    /// Fails if `paused -> completed` is rejected again.
    @Test func completionWhilePausedIsRecorded() {
        let service = OperationStateService()
        _ = start(service)
        service.pauseOperation(reason: .userRequested, currentProgress: nil)
        #expect(service.currentState.isPaused)

        service.completeOperation(success: true, message: "done")

        #expect(service.currentState == .completed(OperationCompletionInfo(success: true, message: "done")))
        #expect(!service.currentState.canResume)
    }

    /// A cancelled start that winds down after a newer transfer began must
    /// not stamp its ending onto the newer one: the screen reads this state.
    /// Fails if the lifecycle calls stop checking the operation ID.
    @Test func staleOperationCannotEndANewerOne() {
        let service = OperationStateService()
        let stale = start(service)
        _ = start(service)

        service.cancelOperation(operationId: stale)
        #expect(service.currentState == .inProgress)
        service.failOperation(operationId: stale)
        #expect(service.currentState == .inProgress)
        service.completeOperation(operationId: stale, success: true, message: "stale")
        #expect(service.currentState == .inProgress)
    }

    /// Resuming is a brief state; the screen must follow it back to
    /// in-progress. Fails if the coordinator keeps a stale copy.
    @Test func resumingSettlesToInProgressOnScreen() async {
        let coordinator = makeCoordinator()
        _ = start(coordinator.stateService)
        await coordinator.pauseOperation()
        #expect(coordinator.operationState.isPaused)

        await coordinator.resumeOperation()
        let settled = await waitUntil(timeout: .seconds(5)) {
            coordinator.operationState == .inProgress
        }
        #expect(settled, "screen state stuck at \(coordinator.operationState)")
    }
}
#endif
