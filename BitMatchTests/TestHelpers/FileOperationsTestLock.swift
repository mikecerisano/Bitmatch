import Foundation

/// Runs `operation` inline, in the caller's isolation. Despite the name it
/// never serialized anything: it used to be an actor, and actors are
/// reentrant at every `await` inside `operation`. Tests that touch the file
/// system use their own temporary folders instead.
final class FileOperationsTestLock: Sendable {
    static let shared = FileOperationsTestLock()

    func run<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        try await operation()
    }
}
