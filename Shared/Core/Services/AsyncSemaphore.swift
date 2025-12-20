// AsyncSemaphore.swift - Shared async concurrency primitive
import Foundation

/// An actor-based semaphore to safely limit concurrency in async contexts.
/// This is the single source of truth for async semaphores across all platforms.
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) {
        self.count = max(0, count)
    }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Convenience wrapper for scoped semaphore usage

/// Execute an async operation while holding a semaphore permit.
/// Automatically releases the permit when the operation completes or throws.
@inline(__always)
func withSemaphore<T>(_ semaphore: AsyncSemaphore, _ operation: () async throws -> T) async rethrows -> T {
    await semaphore.wait()
    do {
        let result = try await operation()
        await semaphore.signal()
        return result
    } catch {
        await semaphore.signal()
        throw error
    }
}
