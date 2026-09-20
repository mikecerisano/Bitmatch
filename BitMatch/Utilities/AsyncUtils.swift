// Utilities/AsyncUtils.swift - Centralized async utilities and patterns
import Foundation

// MARK: - Background Task Utilities

struct BackgroundTask {
    /// Execute work on a background thread and return to main actor for result
    @discardableResult
    static func execute<T: Sendable>(
        priority: TaskPriority = .utility,
        work: @Sendable @escaping () async throws -> T,
        completion: @MainActor @Sendable @escaping (Result<T, Error>) -> Void = { _ in }
    ) -> Task<Void, Never> {
        return Task(priority: priority) {
            do {
                let result = try await work()
                await MainActor.run {
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Async Sequence Utilities

extension AsyncSequence {
    /// Collect all elements from an async sequence into an array
    func collect() async rethrows -> [Element] {
        var result: [Element] = []
        for try await element in self {
            result.append(element)
        }
        return result
    }
    
    /// Process elements in batches of a specified size
    func batched(size: Int) -> AsyncBatchedSequence<Self> {
        AsyncBatchedSequence(base: self, batchSize: size)
    }
}

struct AsyncBatchedSequence<Base: AsyncSequence>: AsyncSequence {
    typealias Element = [Base.Element]
    
    let base: Base
    let batchSize: Int
    
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(baseIterator: base.makeAsyncIterator(), batchSize: batchSize)
    }
    
    struct AsyncIterator: AsyncIteratorProtocol {
        var baseIterator: Base.AsyncIterator
        let batchSize: Int
        
        mutating func next() async throws -> [Base.Element]? {
            var batch: [Base.Element] = []
            
            while batch.count < batchSize {
                if let element = try await baseIterator.next() {
                    batch.append(element)
                } else {
                    break
                }
            }
            
            return batch.isEmpty ? nil : batch
        }
    }
}

// MARK: - Error Handling Utilities

struct RetryHelper {
    /// Execute an async operation with retry logic
    static func withRetry<T: Sendable>(
        maxAttempts: Int = 3,
        delayNanoseconds: UInt64 = 100_000_000, // 100ms
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            }
        }
        
        throw lastError ?? CancellationError()
    }
}

// MARK: - Cancellation Helpers

struct CancellationHelper {
    /// Check for cancellation and throw if cancelled, with optional custom error
    static func checkCancellation(throwing error: Error? = nil) throws {
        if Task.isCancelled {
            throw error ?? CancellationError()
        }
    }
    
    /// Execute work with automatic cancellation checking
    @discardableResult
    static func cancellableWork<T: Sendable>(
        work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        return try await withTaskCancellationHandler {
            try await work()
        } onCancel: {
            // Cancellation cleanup if needed
        }
    }
}

// MARK: - Thread-Safe Collection Utilities

/// A thread-safe wrapper for collections that need to be accessed from multiple contexts
@globalActor
actor CollectionActor {
    static let shared = CollectionActor()
    
    private var storage: [String: Any] = [:]
    
    func store<T>(_ value: T, forKey key: String) {
        storage[key] = value
    }
    
    func retrieve<T>(_ type: T.Type, forKey key: String) -> T? {
        return storage[key] as? T
    }
    
    func remove(forKey key: String) {
        storage.removeValue(forKey: key)
    }
    
    func clear() {
        storage.removeAll()
    }
}
