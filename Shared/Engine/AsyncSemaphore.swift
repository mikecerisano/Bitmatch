// AsyncSemaphore.swift - Shared async concurrency primitive
import Foundation

/// An actor-based semaphore to safely limit concurrency in async contexts.
/// This is the single source of truth for async semaphores across all platforms.
///
/// Cancellation is exact: a waiter cancelled before or while queued throws
/// CancellationError without consuming a permit, so a cancelled waiter never
/// steals a later signal, the count cannot leak, and queued tasks stay
/// collectable. The queue itself is lock-guarded (not actor-isolated)
/// because continuation bodies and cancellation handlers are synchronous
/// and cannot hop to the actor.
public actor AsyncSemaphore {
    private let queue: PermitQueue

    public init(count: Int) {
        self.queue = PermitQueue(count: count)
    }

    /// Acquire a permit, suspending while none is available.
    /// Throws CancellationError when the task is cancelled first.
    public func wait() async throws {
        try Task.checkCancellation()
        if queue.takePermit() { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.enqueueOrResume(id: id, continuation: continuation)
            }
        } onCancel: {
            queue.cancel(id: id)
        }
    }

    public func signal() {
        queue.signal()
    }
}

/// Lock-guarded permit queue. Every method is synchronous and atomic, which
/// closes the race between a cancellation handler firing and the matching
/// enqueue: exactly one of signal()/cancel() wins each waiter, and every
/// waiter is resumed exactly once.
private final class PermitQueue: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var count: Int
    private var waiters: [Waiter] = []

    init(count: Int) {
        self.count = max(0, count)
    }

    /// Take an immediately available permit.
    func takePermit() -> Bool {
        lock.withLock {
            guard count > 0 else { return false }
            count -= 1
            return true
        }
    }

    /// Enqueue, or settle immediately without queueing. Runs on the waiting
    /// task, so Task.isCancelled is authoritative here: a cancelled task
    /// resumes throwing and never appends, which keeps a fired-early
    /// onCancel from orphaning an entry.
    func enqueueOrResume(id: UUID, continuation: CheckedContinuation<Void, Error>) {
        lock.withLock {
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else if count > 0 {
                count -= 1
                continuation.resume()
            } else {
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        }
    }

    /// Drop a queued waiter, resuming it throwing. No-op when signal()
    /// already dequeued it (the holder keeps a real permit, released
    /// through the normal path).
    func cancel(id: UUID) {
        let waiter = lock.withLock { () -> Waiter? in
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
            return waiters.remove(at: index)
        }
        waiter?.continuation.resume(throwing: CancellationError())
    }

    func signal() {
        let next = lock.withLock { () -> Waiter? in
            if waiters.isEmpty {
                count += 1
                return nil
            }
            return waiters.removeFirst()
        }
        next?.continuation.resume()
    }
}

// MARK: - Convenience wrapper for scoped semaphore usage

/// Execute an async operation while holding a semaphore permit.
/// Automatically releases the permit when the operation completes or throws.
/// If acquisition itself is cancelled, the operation never runs and no
/// permit is held or released.
@inline(__always)
public func withSemaphore<T>(_ semaphore: AsyncSemaphore, _ operation: () async throws -> T) async throws -> T {
    try await semaphore.wait()
    do {
        let result = try await operation()
        await semaphore.signal()
        return result
    } catch {
        await semaphore.signal()
        throw error
    }
}
