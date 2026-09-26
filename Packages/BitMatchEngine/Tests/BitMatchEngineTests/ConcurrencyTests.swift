import XCTest
@testable import BitMatchEngine

final class ConcurrencyTests: XCTestCase {

    // MARK: - AsyncSemaphore Basic

    func testSemaphoreBasicWaitSignal() async throws {
        let semaphore = AsyncSemaphore(count: 1)
        try await semaphore.wait()
        // Should have consumed the permit
        await semaphore.signal()
        // Should be able to wait again after signal
        try await semaphore.wait()
        await semaphore.signal()
    }

    func testSemaphoreWithSemaphoreHelper() async throws {
        let semaphore = AsyncSemaphore(count: 2)

        let result = try await withSemaphore(semaphore) {
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    // MARK: - AsyncSemaphore Stress

    func testSemaphoreConcurrentAccess() async {
        let semaphore = AsyncSemaphore(count: 3)
        let counter = Counter()
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    do {
                        try await semaphore.wait()
                    } catch {
                        XCTFail("unexpected semaphore throw: \(error)")
                        return
                    }
                    await counter.increment()
                    // Simulate brief work
                    try? await Task.sleep(nanoseconds: 1_000)
                    await semaphore.signal()
                }
            }
        }

        let finalCount = await counter.value
        XCTAssertEqual(finalCount, iterations)
    }

    func testSemaphoreMaxConcurrency() async {
        let maxConcurrency = 3
        let semaphore = AsyncSemaphore(count: maxConcurrency)
        let concurrencyTracker = ConcurrencyTracker()
        let iterations = 50

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    do {
                        try await semaphore.wait()
                    } catch {
                        XCTFail("unexpected semaphore throw: \(error)")
                        return
                    }
                    let current = await concurrencyTracker.enter()
                    XCTAssertLessThanOrEqual(current, maxConcurrency, "Exceeded max concurrency")
                    // Simulate work
                    try? await Task.sleep(nanoseconds: 10_000)
                    await concurrencyTracker.exit()
                    await semaphore.signal()
                }
            }
        }
    }

    func testSemaphoreWithCancellation() async throws {
        let semaphore = AsyncSemaphore(count: 1)
        try await semaphore.wait() // consume the only permit

        let task = Task {
            // This should wait since permit is consumed
            try await semaphore.wait()
            return true
        }

        // Give it a moment, then cancel
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        // Deterministic: the cancelled waiter always completes (either
        // dequeued by cancel, or holding a real permit after winning
        // the race with the signal below).
        _ = try? await task.value

        // Release the permit
        await semaphore.signal()

        // The permit is intact: a fresh wait succeeds immediately.
        try await semaphore.wait()
        await semaphore.signal()
    }

    /// A waiter cancelled while queued must not consume a later signal.
    /// `try?` keeps this compiling both before the fix (non-throwing wait)
    /// and after (throwing wait).
    func testCancelledWaiterDoesNotStealNextPermit() async {
        let semaphore = AsyncSemaphore(count: 1)
        try? await semaphore.wait() // consume the only permit

        let waiter = Task {
            try? await semaphore.wait()
            return true
        }
        // Let it enqueue, then cancel while queued.
        try? await Task.sleep(nanoseconds: 50_000_000)
        waiter.cancel()
        // Release the permit. Buggy behavior: the dead waiter consumes this
        // signal and the count never recovers.
        await semaphore.signal()

        // A fresh waiter must acquire promptly; the timeout race keeps this
        // deterministic: false means the permit leaked.
        let acquired = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                try? await semaphore.wait()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertTrue(acquired, "cancelled waiter consumed the signalled permit")
        await semaphore.signal()
        _ = await waiter.value
    }

    // MARK: - WithSemaphore Stress

    func testWithSemaphoreStress() async {
        let semaphore = AsyncSemaphore(count: 5)
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    do {
                        try await withSemaphore(semaphore) {
                            await counter.increment()
                        }
                    } catch {
                        XCTFail("unexpected semaphore throw: \(error)")
                    }
                }
            }
        }

        let finalCount = await counter.value
        XCTAssertEqual(finalCount, 200)
    }
}

// MARK: - Test Helpers

private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

private actor ConcurrencyTracker {
    private var current: Int = 0
    private var peak: Int = 0

    func enter() -> Int {
        current += 1
        if current > peak { peak = current }
        return current
    }

    func exit() {
        current -= 1
    }

    var peakConcurrency: Int { peak }
}
