import XCTest
@testable import BitMatch

/// Regression tests for crash-resume detection.
/// saveState encodes dates as ISO-8601, but checkForInterruptedOperations
/// previously decoded with a default JSONDecoder — every state file failed
/// to decode and interrupted operations were never detected. The initial
/// state was also saved with totalCount 0 and checkpoints never updated it,
/// so the `processedCount < totalCount` test could never pass either.
final class OperationStateManagerTests: XCTestCase {

    private var savedIDs: [UUID] = []

    override func tearDown() {
        for id in savedIDs {
            OperationStateManager.clearState(for: id)
        }
        savedIDs = []
        super.tearDown()
    }

    private func makeOperation(
        id: UUID = UUID(),
        startTime: Date,
        processedCount: Int,
        totalCount: Int
    ) -> OperationStateManager.PersistedOperation {
        savedIDs.append(id)
        return OperationStateManager.PersistedOperation(
            id: id,
            startTime: startTime,
            mode: "copy",
            sourceURL: URL(fileURLWithPath: "/tmp/source"),
            destinationURLs: [URL(fileURLWithPath: "/tmp/dest")],
            verificationMode: "standard",
            lastProcessedFile: "clip.mov",
            processedCount: processedCount,
            totalCount: totalCount,
            checkpoints: []
        )
    }

    func testStaleIncompleteOperationIsDetectedAsInterrupted() {
        let operation = makeOperation(
            startTime: Date().addingTimeInterval(-2 * 3600),
            processedCount: 5,
            totalCount: 10
        )
        OperationStateManager.saveState(operation)

        let interrupted = OperationStateManager.checkForInterruptedOperations()
        XCTAssertTrue(
            interrupted.contains { $0.id == operation.id },
            "A stale, incomplete state file must be detected as interrupted"
        )
    }

    func testCompletedOperationIsNotDetectedAsInterrupted() {
        let operation = makeOperation(
            startTime: Date().addingTimeInterval(-2 * 3600),
            processedCount: 10,
            totalCount: 10
        )
        OperationStateManager.saveState(operation)

        let interrupted = OperationStateManager.checkForInterruptedOperations()
        XCTAssertFalse(interrupted.contains { $0.id == operation.id })
    }

    func testCheckpointCanUpdateTotalCount() {
        // The initial state is saved before the file count is known
        // (totalCount 0); checkpoints must be able to fill it in, otherwise
        // `processedCount < totalCount` can never hold.
        let operation = makeOperation(
            startTime: Date().addingTimeInterval(-2 * 3600),
            processedCount: 0,
            totalCount: 0
        )
        OperationStateManager.saveState(operation)

        OperationStateManager.createCheckpoint(
            for: operation.id,
            filesProcessed: 5,
            lastFile: "clip.mov",
            totalCount: 10
        )

        let loaded = OperationStateManager.loadState(for: operation.id)
        XCTAssertEqual(loaded?.totalCount, 10)
        XCTAssertEqual(loaded?.processedCount, 5)
    }
}
