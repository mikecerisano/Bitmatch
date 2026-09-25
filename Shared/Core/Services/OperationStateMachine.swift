// OperationStateMachine.swift - Transition rules for OperationStateService
import Foundation

/// Validates operation state transitions for `OperationStateService`, which drives
/// pause/resume. It is not the only record of operation state:
/// `SharedAppCoordinator.operationState` (the displayed verdict) is written
/// separately and can diverge when a transition here is rejected.
@MainActor
final class OperationStateMachine: ObservableObject {
    @Published private(set) var currentState: OperationState = .notStarted

    /// Valid transitions map
    private static let validTransitions: [String: Set<String>] = [
        "notStarted": ["inProgress"],
        "idle": ["inProgress"],
        "inProgress": ["copying", "verifying", "paused", "completed", "failed", "cancelled"],
        "copying": ["verifying", "paused", "completed", "failed", "cancelled"],
        "verifying": ["completed", "paused", "failed", "cancelled"],
        // A run that finishes while paused or resuming (an automatic pause
        // racing the last file) must still record how it ended.
        "paused": ["resuming", "completed", "failed", "cancelled"],
        "resuming": ["inProgress", "copying", "verifying", "completed", "failed", "cancelled"],
        "completed": ["notStarted", "idle"],
        "failed": ["notStarted", "idle"],
        "cancelled": ["notStarted", "idle"],
    ]

    /// Attempt a state transition; returns true if valid
    @discardableResult
    func transition(to newState: OperationState) -> Bool {
        let currentKey = stateKey(currentState)
        let newKey = stateKey(newState)

        guard let allowed = Self.validTransitions[currentKey], allowed.contains(newKey) else {
            SharedLogger.warning("Invalid state transition: \(currentKey) -> \(newKey)", category: .transfer)
            return false
        }

        currentState = newState
        return true
    }

    /// Force reset to initial state (e.g., on app launch)
    func reset() {
        currentState = .notStarted
    }

    /// Set a state reported by the coordinator or the engine without
    /// rejecting it, so the one stored state always matches what actually
    /// happened. Returns whether it was a listed transition; unlisted ones
    /// are logged for review.
    @discardableResult
    func adopt(_ newState: OperationState) -> Bool {
        let listed = currentState == newState
            || Self.validTransitions[stateKey(currentState)]?.contains(stateKey(newState)) == true
        if !listed {
            SharedLogger.warning("Adopted unlisted state transition: \(stateKey(currentState)) -> \(stateKey(newState))", category: .transfer)
        }
        currentState = newState
        return listed
    }

    /// Rehydrate a persisted paused state (e.g., after relaunch). This is not
    /// a normal transition — it restores state from disk without validation.
    func restorePaused(_ info: PauseInfo) {
        currentState = .paused(info)
    }

    // MARK: - Convenience Transitions

    func startOperation() -> Bool {
        transition(to: .inProgress)
    }

    func beginCopying() -> Bool {
        transition(to: .copying)
    }

    func beginVerifying() -> Bool {
        transition(to: .verifying)
    }

    func pause(info: PauseInfo) -> Bool {
        transition(to: .paused(info))
    }

    func resume() -> Bool {
        transition(to: .resuming)
    }

    func complete(info: OperationCompletionInfo) -> Bool {
        transition(to: .completed(info))
    }

    func fail() -> Bool {
        transition(to: .failed)
    }

    func cancel() -> Bool {
        transition(to: .cancelled)
    }

    // MARK: - Private

    private func stateKey(_ state: OperationState) -> String {
        switch state {
        case .idle: return "idle"
        case .notStarted: return "notStarted"
        case .inProgress: return "inProgress"
        case .copying: return "copying"
        case .verifying: return "verifying"
        case .paused: return "paused"
        case .resuming: return "resuming"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        }
    }
}
