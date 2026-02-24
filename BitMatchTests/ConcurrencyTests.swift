import XCTest
@testable import BitMatch

final class ConcurrencyTests: XCTestCase {

    // MARK: - AsyncSemaphore Basic

    func testSemaphoreBasicWaitSignal() async {
        let semaphore = AsyncSemaphore(count: 1)
        await semaphore.wait()
        // Should have consumed the permit
        await semaphore.signal()
        // Should be able to wait again after signal
        await semaphore.wait()
        await semaphore.signal()
    }

    func testSemaphoreWithSemaphoreHelper() async throws {
        let semaphore = AsyncSemaphore(count: 2)

        let result = await withSemaphore(semaphore) {
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
                    await semaphore.wait()
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
                    await semaphore.wait()
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

    func testSemaphoreWithCancellation() async {
        let semaphore = AsyncSemaphore(count: 1)
        await semaphore.wait() // consume the only permit

        let task = Task {
            // This should wait since permit is consumed
            await semaphore.wait()
            return true
        }

        // Give it a moment, then cancel
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        // Release the permit
        await semaphore.signal()

        // The cancelled task may or may not complete depending on timing
        // Just ensure no crash
    }

    // MARK: - WithSemaphore Stress

    func testWithSemaphoreStress() async {
        let semaphore = AsyncSemaphore(count: 5)
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    await withSemaphore(semaphore) {
                        await counter.increment()
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
