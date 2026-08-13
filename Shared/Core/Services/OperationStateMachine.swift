// OperationStateMachine.swift - Single source of truth for operation state transitions
// Phase 3: Consolidate state management from SharedAppCoordinator + OperationStateService
import Foundation

/// Validates and manages operation state transitions
/// Ensures only valid transitions occur and provides a single source of truth
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
        "paused": ["resuming", "cancelled"],
        "resuming": ["inProgress", "copying", "verifying", "failed", "cancelled"],
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
