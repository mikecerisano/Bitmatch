import Foundation

actor FileOperationsTestLock {
    static let shared = FileOperationsTestLock()

    func run<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await operation()
    }
}
