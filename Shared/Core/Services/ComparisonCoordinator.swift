// ComparisonCoordinator.swift - The app's handle on a folder comparison.
import Foundation
import BitMatchEngine

/// Runs one `FolderComparer` at a time for `SharedAppCoordinator` and lets it
/// be cancelled from the main actor.
@MainActor
final class ComparisonCoordinator {
    private let platformManager: PlatformManager
    private var cancellationRequested = false
    private var running: Task<CompareStats, Error>?

    init(platformManager: PlatformManager) {
        self.platformManager = platformManager
    }

    func requestCancellation() {
        cancellationRequested = true
        running?.cancel()
    }

    /// Observable for callers that publish results after the comparison returns,
    /// so a cancellation landing in the final checksum work cannot surface as
    /// a normal completion.
    var isCancellationRequested: Bool { cancellationRequested }

    /// Compare two folders and return stats
    func compareFolders(
        left: URL,
        right: URL,
        verificationMode: VerificationMode,
        onProgress: @escaping @MainActor @Sendable (OperationProgress) -> Void
    ) async throws -> CompareStats {
        cancellationRequested = false
        let comparer = FolderComparer(
            fileAccess: platformManager.fileSystem,
            checksum: platformManager.checksum
        )
        let task = Task {
            try await comparer.compare(left: left, right: right, verificationMode: verificationMode) { progress in
                await onProgress(progress)
            }
        }
        running = task
        defer { if running == task { running = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
