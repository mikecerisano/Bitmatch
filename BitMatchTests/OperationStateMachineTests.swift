import XCTest
@testable import BitMatch

@MainActor
final class OperationStateMachineTests: XCTestCase {
    var stateMachine: OperationStateMachine!

    override func setUp() {
        super.setUp()
        stateMachine = OperationStateMachine()
    }

    // MARK: - Helpers

    private func makePauseInfo(reason: PauseInfo.PauseReason = .userRequested) -> PauseInfo {
        PauseInfo(
            pausedAt: Date(),
            currentFile: "test_file.mov",
            filesProcessed: 5,
            totalFiles: 10,
            bytesProcessed: 1024,
            reason: reason
        )
    }

    private func makeCompletionInfo(success: Bool = true, message: String = "Done") -> OperationCompletionInfo {
        OperationCompletionInfo(success: success, message: message)
    }

    // MARK: - Initial State

    func testInitialState() {
        switch stateMachine.currentState {
        case .notStarted: break // expected
        default: XCTFail("Initial state should be .notStarted, got \(stateMachine.currentState)")
        }
    }

    // MARK: - Valid Transitions from notStarted

    func testNotStartedToInProgress() {
        XCTAssertTrue(stateMachine.startOperation())
        switch stateMachine.currentState {
        case .inProgress: break
        default: XCTFail("Expected .inProgress, got \(stateMachine.currentState)")
        }
    }

    // MARK: - Valid Transitions from idle

    func testIdleToInProgress() {
        // Get to idle via completed -> idle
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertTrue(stateMachine.transition(to: .idle))
        XCTAssertTrue(stateMachine.startOperation())
        switch stateMachine.currentState {
        case .inProgress: break
        default: XCTFail("Expected .inProgress, got \(stateMachine.currentState)")
        }
    }

    // MARK: - Valid Transitions from inProgress

    func testInProgressToCopying() {
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.beginCopying())
        switch stateMachine.currentState {
        case .copying: break
        default: XCTFail("Expected .copying, got \(stateMachine.currentState)")
        }
    }

    func testInProgressToVerifying() {
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.beginVerifying())
        switch stateMachine.currentState {
        case .verifying: break
        default: XCTFail("Expected .verifying, got \(stateMachine.currentState)")
        }
    }

    func testInProgressToPaused() {
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
        switch stateMachine.currentState {
        case .paused: break
        default: XCTFail("Expected .paused, got \(stateMachine.currentState)")
        }
    }

    func testInProgressToCompleted() {
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testInProgressToFailed() {
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.fail())
        XCTAssertEqual(stateMachine.currentState, .failed)
    }

    func testInProgressToCancelled() {
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.cancel())
        XCTAssertEqual(stateMachine.currentState, .cancelled)
    }

    // MARK: - Valid Transitions from copying

    func testCopyingToVerifying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.beginVerifying())
        switch stateMachine.currentState {
        case .verifying: break
        default: XCTFail("Expected .verifying, got \(stateMachine.currentState)")
        }
    }

    func testCopyingToPaused() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
    }

    func testCopyingToCompleted() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testCopyingToFailed() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.fail())
    }

    func testCopyingToCancelled() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.cancel())
    }

    // MARK: - Valid Transitions from verifying

    func testVerifyingToCompleted() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testVerifyingToPaused() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
    }

    func testVerifyingToFailed() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertTrue(stateMachine.fail())
    }

    func testVerifyingToCancelled() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertTrue(stateMachine.cancel())
    }

    // MARK: - Valid Transitions from paused

    func testPausedToResuming() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertTrue(stateMachine.resume())
        switch stateMachine.currentState {
        case .resuming: break
        default: XCTFail("Expected .resuming, got \(stateMachine.currentState)")
        }
    }

    func testPausedToCancelled() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertTrue(stateMachine.cancel())
        XCTAssertEqual(stateMachine.currentState, .cancelled)
    }

    // MARK: - Valid Transitions from resuming

    func testResumingToInProgress() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        stateMachine.resume()
        XCTAssertTrue(stateMachine.transition(to: .inProgress))
    }

    func testResumingToCopying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        stateMachine.resume()
        XCTAssertTrue(stateMachine.beginCopying())
    }

    func testResumingToVerifying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        stateMachine.resume()
        XCTAssertTrue(stateMachine.beginVerifying())
    }

    func testResumingToFailed() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        stateMachine.resume()
        XCTAssertTrue(stateMachine.fail())
    }

    func testResumingToCancelled() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        stateMachine.resume()
        XCTAssertTrue(stateMachine.cancel())
    }

    // MARK: - Valid Transitions from terminal states

    func testCompletedToNotStarted() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
    }

    func testCompletedToIdle() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertTrue(stateMachine.transition(to: .idle))
    }

    func testFailedToNotStarted() {
        stateMachine.startOperation()
        stateMachine.fail()
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
    }

    func testFailedToIdle() {
        stateMachine.startOperation()
        stateMachine.fail()
        XCTAssertTrue(stateMachine.transition(to: .idle))
    }

    func testCancelledToNotStarted() {
        stateMachine.startOperation()
        stateMachine.cancel()
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
    }

    func testCancelledToIdle() {
        stateMachine.startOperation()
        stateMachine.cancel()
        XCTAssertTrue(stateMachine.transition(to: .idle))
    }

    // MARK: - Invalid Transitions

    func testCannotGoFromNotStartedToCopying() {
        XCTAssertFalse(stateMachine.beginCopying())
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("State should not change on invalid transition")
        }
    }

    func testCannotGoFromNotStartedToVerifying() {
        XCTAssertFalse(stateMachine.beginVerifying())
    }

    func testCannotGoFromNotStartedToCompleted() {
        XCTAssertFalse(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testCannotGoFromNotStartedToFailed() {
        XCTAssertFalse(stateMachine.fail())
    }

    func testCannotGoFromNotStartedToCancelled() {
        XCTAssertFalse(stateMachine.cancel())
    }

    func testCannotGoFromNotStartedToPaused() {
        XCTAssertFalse(stateMachine.pause(info: makePauseInfo()))
    }

    func testCannotGoFromNotStartedToResuming() {
        XCTAssertFalse(stateMachine.resume())
    }

    func testCannotGoFromCompletedToCopying() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertFalse(stateMachine.beginCopying())
    }

    func testCannotGoFromCompletedToVerifying() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertFalse(stateMachine.beginVerifying())
    }

    func testCannotGoFromCompletedToFailed() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertFalse(stateMachine.fail())
    }

    func testCannotGoFromCompletedToPaused() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        XCTAssertFalse(stateMachine.pause(info: makePauseInfo()))
    }

    func testCannotGoFromPausedToCopying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertFalse(stateMachine.beginCopying())
    }

    func testCannotGoFromPausedToVerifying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertFalse(stateMachine.beginVerifying())
    }

    func testCannotGoFromPausedToInProgress() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertFalse(stateMachine.transition(to: .inProgress))
    }

    func testCannotGoFromPausedToCompleted() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertFalse(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testCannotGoFromPausedToFailed() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertFalse(stateMachine.fail())
    }

    func testCannotGoFromVerifyingToCopying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertFalse(stateMachine.beginCopying())
    }

    func testCannotGoFromVerifyingToInProgress() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertFalse(stateMachine.transition(to: .inProgress))
    }

    func testCannotGoFromFailedToCopying() {
        stateMachine.startOperation()
        stateMachine.fail()
        XCTAssertFalse(stateMachine.beginCopying())
    }

    func testCannotGoFromFailedToInProgress() {
        stateMachine.startOperation()
        stateMachine.fail()
        XCTAssertFalse(stateMachine.startOperation())
    }

    func testCannotGoFromCancelledToCopying() {
        stateMachine.startOperation()
        stateMachine.cancel()
        XCTAssertFalse(stateMachine.beginCopying())
    }

    func testCannotGoFromCancelledToInProgress() {
        stateMachine.startOperation()
        stateMachine.cancel()
        XCTAssertFalse(stateMachine.startOperation())
    }

    // MARK: - State Preservation on Invalid Transition

    func testStatePreservedOnInvalidTransition() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        // Attempt invalid transition: copying -> notStarted
        XCTAssertFalse(stateMachine.transition(to: .notStarted))
        switch stateMachine.currentState {
        case .copying: break
        default: XCTFail("State should remain .copying after invalid transition, got \(stateMachine.currentState)")
        }
    }

    func testStatePreservedOnMultipleInvalidTransitions() {
        stateMachine.startOperation()
        XCTAssertFalse(stateMachine.transition(to: .notStarted))
        XCTAssertFalse(stateMachine.transition(to: .idle))
        XCTAssertFalse(stateMachine.resume())
        switch stateMachine.currentState {
        case .inProgress: break
        default: XCTFail("State should remain .inProgress, got \(stateMachine.currentState)")
        }
    }

    // MARK: - Reset

    func testResetFromNotStarted() {
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testResetFromInProgress() {
        stateMachine.startOperation()
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testResetFromCopying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testResetFromPaused() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testResetFromCompleted() {
        stateMachine.startOperation()
        stateMachine.complete(info: makeCompletionInfo())
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testResetFromFailed() {
        stateMachine.startOperation()
        stateMachine.fail()
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testResetFromCancelled() {
        stateMachine.startOperation()
        stateMachine.cancel()
        stateMachine.reset()
        switch stateMachine.currentState {
        case .notStarted: break
        default: XCTFail("Reset should return to .notStarted")
        }
    }

    func testCanStartOperationAfterReset() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.reset()
        XCTAssertTrue(stateMachine.startOperation())
        switch stateMachine.currentState {
        case .inProgress: break
        default: XCTFail("Should be able to start operation after reset")
        }
    }

    // MARK: - Full Lifecycle

    func testFullSuccessfulLifecycle() {
        XCTAssertTrue(stateMachine.startOperation())
        XCTAssertTrue(stateMachine.beginCopying())
        XCTAssertTrue(stateMachine.beginVerifying())
        let info = makeCompletionInfo(success: true, message: "All files verified")
        XCTAssertTrue(stateMachine.complete(info: info))
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
    }

    func testLifecycleWithPauseAndResumeToCopying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
        XCTAssertTrue(stateMachine.resume())
        // After resuming, can go back to copying
        XCTAssertTrue(stateMachine.beginCopying())
        XCTAssertTrue(stateMachine.beginVerifying())
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testLifecycleWithPauseAndResumeToVerifying() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.beginVerifying()
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
        XCTAssertTrue(stateMachine.resume())
        XCTAssertTrue(stateMachine.beginVerifying())
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testLifecycleWithFailureAndRestart() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.fail())
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
        // Can restart after failure
        XCTAssertTrue(stateMachine.startOperation())
        XCTAssertTrue(stateMachine.beginCopying())
        XCTAssertTrue(stateMachine.beginVerifying())
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testLifecycleWithCancellationAndRestart() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        XCTAssertTrue(stateMachine.cancel())
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
        // Can restart after cancellation
        XCTAssertTrue(stateMachine.startOperation())
        XCTAssertTrue(stateMachine.beginCopying())
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testLifecycleCancelFromPaused() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        stateMachine.pause(info: makePauseInfo())
        XCTAssertTrue(stateMachine.cancel())
        XCTAssertTrue(stateMachine.transition(to: .notStarted))
    }

    func testLifecycleMultiplePauseResumeCycles() {
        stateMachine.startOperation()
        stateMachine.beginCopying()

        // First pause/resume
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
        XCTAssertTrue(stateMachine.resume())
        XCTAssertTrue(stateMachine.beginCopying())

        // Second pause/resume
        XCTAssertTrue(stateMachine.pause(info: makePauseInfo()))
        XCTAssertTrue(stateMachine.resume())
        XCTAssertTrue(stateMachine.beginVerifying())

        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    func testLifecycleDirectInProgressToCompleted() {
        // Some operations may skip copying/verifying phases
        stateMachine.startOperation()
        XCTAssertTrue(stateMachine.complete(info: makeCompletionInfo()))
    }

    // MARK: - PauseInfo Reasons

    func testPauseWithDifferentReasons() {
        let reasons: [PauseInfo.PauseReason] = [
            .userRequested,
            .systemSleep,
            .lowBattery,
            .backgrounded,
            .error,
        ]

        for reason in reasons {
            stateMachine.reset()
            stateMachine.startOperation()
            stateMachine.beginCopying()
            let pauseInfo = makePauseInfo(reason: reason)
            XCTAssertTrue(stateMachine.pause(info: pauseInfo), "Should be able to pause with reason: \(reason)")
        }
    }

    // MARK: - Completion Info

    func testCompleteWithSuccessInfo() {
        stateMachine.startOperation()
        let info = makeCompletionInfo(success: true, message: "All 100 files verified successfully")
        XCTAssertTrue(stateMachine.complete(info: info))
        switch stateMachine.currentState {
        case .completed(let completionInfo):
            XCTAssertTrue(completionInfo.success)
            XCTAssertEqual(completionInfo.message, "All 100 files verified successfully")
        default:
            XCTFail("Expected .completed state")
        }
    }

    func testCompleteWithFailureInfo() {
        stateMachine.startOperation()
        let info = makeCompletionInfo(success: false, message: "3 files failed verification")
        XCTAssertTrue(stateMachine.complete(info: info))
        switch stateMachine.currentState {
        case .completed(let completionInfo):
            XCTAssertFalse(completionInfo.success)
            XCTAssertEqual(completionInfo.message, "3 files failed verification")
        default:
            XCTFail("Expected .completed state")
        }
    }

    // MARK: - Paused State Data

    func testPausedStatePreservesInfo() {
        stateMachine.startOperation()
        stateMachine.beginCopying()
        let pauseInfo = PauseInfo(
            pausedAt: Date(),
            currentFile: "important_video.mov",
            filesProcessed: 42,
            totalFiles: 100,
            bytesProcessed: 1_073_741_824,
            reason: .userRequested
        )
        stateMachine.pause(info: pauseInfo)
        switch stateMachine.currentState {
        case .paused(let info):
            XCTAssertEqual(info.currentFile, "important_video.mov")
            XCTAssertEqual(info.filesProcessed, 42)
            XCTAssertEqual(info.totalFiles, 100)
            XCTAssertEqual(info.bytesProcessed, 1_073_741_824)
            XCTAssertEqual(info.reason, .userRequested)
        default:
            XCTFail("Expected .paused state with info")
        }
    }
}
