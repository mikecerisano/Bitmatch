// ConcurrencyHelpers.swift - macOS-specific concurrency gates
// Uses shared AsyncSemaphore from Shared/Core/Services/AsyncSemaphore.swift
import Foundation

let BigFileGate = AsyncSemaphore(
    count: ProcessInfo.processInfo.activeProcessorCount > 8 ? 3 : 2
)

@inline(__always)
func withBigFileGate<T>(_ op: () async throws -> T) async rethrows -> T {
    await BigFileGate.wait()
    do {
        let result = try await op()
        await BigFileGate.signal()
        return result
    } catch {
        await BigFileGate.signal()
        throw error
    }
}


// Gate to prevent I/O thrashing when checksumming many files in parallel
let ChecksumGate = AsyncSemaphore(count: max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

@inline(__always)
func withChecksumGate<T>(_ op: () async throws -> T) async rethrows -> T {
    await ChecksumGate.wait()
    do {
        let result = try await op()
        await ChecksumGate.signal()
        return result
    } catch {
        await ChecksumGate.signal()
        throw error
    }
}

// Gate for concurrent file copy operations to prevent filesystem overload
let FileCopyGate = AsyncSemaphore(count: max(4, ProcessInfo.processInfo.activeProcessorCount))

@inline(__always)
func withFileCopyGate<T>(_ op: () async throws -> T) async rethrows -> T {
    await FileCopyGate.wait()
    do {
        let result = try await op()
        await FileCopyGate.signal()
        return result
    } catch {
        await FileCopyGate.signal()
        throw error
    }
}
