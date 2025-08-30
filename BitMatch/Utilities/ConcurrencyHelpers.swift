import Foundation
import Darwin

/// An actor-based semaphore to safely limit concurrency in async contexts.
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { self.count = count }

    func wait() async {
        if count > 0 { count -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty { count += 1 }
        else { waiters.removeFirst().resume() }
    }
}

let BigFileGate = AsyncSemaphore(
    count: ProcessInfo.processInfo.activeProcessorCount > 8 ? 3 : 2
)

@inline(__always)
func withBigFileGate<T>(_ op: () async throws -> T) async rethrows -> T {
    await BigFileGate.wait()
    defer { Task { await BigFileGate.signal() } }
    return try await op()
}


// Gate to prevent I/O thrashing when checksumming many files in parallel
let ChecksumGate = AsyncSemaphore(count: max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

@inline(__always)
func withChecksumGate<T>(_ op: () async throws -> T) async rethrows -> T {
    await ChecksumGate.wait()
    defer { Task { await ChecksumGate.signal() } }
    return try await op()
}

// Gate for concurrent file copy operations to prevent filesystem overload
let FileCopyGate = AsyncSemaphore(count: max(4, ProcessInfo.processInfo.activeProcessorCount))

@inline(__always)
func withFileCopyGate<T>(_ op: () async throws -> T) async rethrows -> T {
    await FileCopyGate.wait()
    defer { Task { await FileCopyGate.signal() } }
    return try await op()
}
