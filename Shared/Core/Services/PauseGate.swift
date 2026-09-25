// PauseGate.swift - One run's pause switch.
import Foundation
import Synchronization

/// Pauses the work of one transfer. `wait()` returns at once while the gate
/// is open, and parks while it is paused until `resume()` or cancellation.
/// Waiters are woken, not polled, and a cancelled waiter always throws
/// `CancellationError` and is never left parked.
///
/// A run installs its gate as `PauseGate.current` for its own task tree, so
/// checksum and destination reads deep in the engine pause with that run and
/// no other. Work outside a run (Compare, off-site checks) sees no gate.
final class PauseGate: Sendable {
    @TaskLocal static var current: PauseGate?

    /// Waits on the current run's gate, if there is one.
    static func waitIfCurrentIsPaused() async throws {
        try await current?.wait()
    }

    private struct State {
        var paused = false
        var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    }

    private let state = Mutex(State())

    var isPaused: Bool { state.withLock { $0.paused } }

    func pause() {
        state.withLock { $0.paused = true }
    }

    func resume() {
        let waiters = state.withLock { state in
            state.paused = false
            defer { state.waiters.removeAll() }
            return Array(state.waiters.values)
        }
        waiters.forEach { $0.resume() }
    }

    func wait() async throws {
        try Task.checkCancellation()
        guard isPaused else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Decide under the lock so a resume or cancel that races
                // this registration cannot be missed.
                let immediate: Result<Void, Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    guard state.paused else { return .success(()) }
                    state.waiters[id] = continuation
                    return nil
                }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            let continuation = state.withLock { $0.waiters.removeValue(forKey: id) }
            continuation?.resume(throwing: CancellationError())
        }
    }
}
