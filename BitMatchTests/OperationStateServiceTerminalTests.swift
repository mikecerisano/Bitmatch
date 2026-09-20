import Foundation
import Testing
@testable import BitMatch

/// The coordinator's terminal callbacks (.completed/.failed/.cancelled) must
/// agree with OperationStateService. Completion previously cleared the
/// operation ID without transitioning state, and errors left the service in
/// .cancelled while the coordinator reported .failed.
@MainActor
struct OperationStateServiceTerminalTests {
    private func startedService() -> (OperationStateService, UUID) {
        let service = OperationStateService()
        let id = UUID()
        service.startOperation(
            id: id,
            sourceURL: URL(fileURLWithPath: "/tmp/bitmatch-source"),
            destinationURLs: [URL(fileURLWithPath: "/tmp/bitmatch-dest")],
            totalFiles: 1,
            totalBytes: 1
        )
        return (service, id)
    }

    @Test func completionTransitionsToCompleted() {
        let (service, _) = startedService()
        service.completeOperation(success: true, message: "done")
        guard case .completed(let info) = service.currentState else {
            Issue.record("expected .completed, got \(service.currentState)")
            return
        }
        #expect(info.success)
        #expect(info.message == "done")
    }

    @Test func failureTransitionsToFailed() {
        let (service, _) = startedService()
        service.failOperation()
        #expect(service.currentState == .failed)
    }

    @Test func cancellationTransitionsToCancelled() {
        let (service, _) = startedService()
        service.cancelOperation()
        #expect(service.currentState == .cancelled)
    }
}
