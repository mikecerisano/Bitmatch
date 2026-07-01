import XCTest
@testable import BitMatch

/// Regression tests for the master report "verified" flag.
/// TransferCard.verified previously returned true for any `.completed`
/// state, discarding OperationCompletionInfo.success — so master reports
/// stamped "verified" on transfers that completed with failures.
final class TransferCardVerificationTests: XCTestCase {

    private func makeCard(state: OperationState) -> TransferCard {
        let folder = FolderInfo(
            url: URL(fileURLWithPath: "/tmp/source"),
            fileCount: 10,
            totalSize: 1_000,
            lastModified: Date(),
            isInternalDrive: false
        )
        return TransferCard(
            source: folder,
            destinations: [folder],
            cameraCard: nil,
            metadata: nil,
            progress: 1.0,
            state: state
        )
    }

    func testCompletedWithSuccessIsVerified() {
        let card = makeCard(state: .completed(OperationCompletionInfo(success: true, message: "ok")))
        XCTAssertTrue(card.verified)
    }

    func testCompletedWithFailuresIsNotVerified() {
        let card = makeCard(state: .completed(OperationCompletionInfo(success: false, message: "3 issues")))
        XCTAssertFalse(card.verified)
    }

    func testNonCompletedStatesAreNotVerified() {
        XCTAssertFalse(makeCard(state: .inProgress).verified)
        XCTAssertFalse(makeCard(state: .failed).verified)
        XCTAssertFalse(makeCard(state: .cancelled).verified)
    }

    // MARK: - CompareStats

    func testCompareStatsCleanWhenNoDifferences() {
        let stats = CompareStats(onlyInLeftCount: 0, onlyInRightCount: 0, commonCount: 5, mismatchedCount: 0)
        XCTAssertTrue(stats.isClean)
    }

    func testCompareStatsNotCleanWithMismatches() {
        let stats = CompareStats(onlyInLeftCount: 0, onlyInRightCount: 0, commonCount: 5, mismatchedCount: 1)
        XCTAssertFalse(stats.isClean)
    }

    func testCompareStatsNotCleanWithMissingFiles() {
        let missingInRight = CompareStats(onlyInLeftCount: 2, onlyInRightCount: 0, commonCount: 5, mismatchedCount: 0)
        XCTAssertFalse(missingInRight.isClean)

        let extraInRight = CompareStats(onlyInLeftCount: 0, onlyInRightCount: 2, commonCount: 5, mismatchedCount: 0)
        XCTAssertFalse(extraInRight.isClean)
    }
}
