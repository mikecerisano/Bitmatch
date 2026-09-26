// PauseGateTests.swift
import Foundation
import Testing
@testable import BitMatchEngine

@Suite(.timeLimit(.minutes(1)))
struct PauseGateTests {
    @Test func openGateDoesNotWait() async throws {
        let gate = PauseGate()
        try await gate.wait()
        #expect(!gate.isPaused)
    }

    /// Plant: make `resume()` skip waking the waiters.
    @Test func pausedGateHoldsEveryWaiterUntilResume() async throws {
        let gate = PauseGate()
        gate.pause()
        let released = Counter()
        let waiters = (0..<3).map { _ in
            Task { try await gate.wait(); released.increment() }
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(released.value == 0)

        gate.resume()
        for waiter in waiters { try await waiter.value }
        #expect(released.value == 3)
    }

    /// Plant: in `wait()`'s cancellation handler, do not resume the continuation.
    @Test func cancelledWaiterThrowsAndIsNotLeftParked() async throws {
        let gate = PauseGate()
        gate.pause()
        let waiter = Task { try await gate.wait() }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(gate.isPaused, "cancelling one waiter must not open the gate")
    }

    @Test func cancelledTaskThrowsEvenWhenOpen() async throws {
        let gate = PauseGate()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await gate.wait()
        }
        await #expect(throws: CancellationError.self) { try await waiter.value }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
