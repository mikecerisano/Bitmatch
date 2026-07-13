import XCTest
@testable import BitMatch

final class ResultPresentationTests: XCTestCase {
    func testSidecarFailureMakesIntegritySummaryFail() {
        let rows = [
            row("clip.mov", status: "✅ Verified"),
            row("clip.xml", status: "⚠️ Checksum Mismatch"),
        ]

        let summary = ResultIntegritySummary(rows: rows)

        XCTAssertEqual(summary.successfulRows.map(\.fileName), ["clip.mov"])
        XCTAssertEqual(summary.issueRows.map(\.fileName), ["clip.xml"])
        XCTAssertFalse(summary.isSuccessful)
    }

    func testUnknownStatusIsAnIntegrityIssue() {
        let summary = ResultIntegritySummary(rows: [row("clip.xml", status: "Unknown")])

        XCTAssertEqual(summary.issueRows.map(\.fileName), ["clip.xml"])
        XCTAssertFalse(summary.isSuccessful)
    }

    func testCompletedFalseResolvesToIssuesWithoutDiagnosticError() {
        let verdict = CompletionVerdict.resolve(
            state: .completed(OperationCompletionInfo(success: false, message: "1 issue")),
            rows: [row("clip.xml", status: "⚠️ Checksum Mismatch")],
            hasErrors: false,
            hasCriticalErrors: false
        )

        XCTAssertEqual(verdict, .issues)
    }

    func testFailedRowOverridesCompletedTrueState() {
        let verdict = CompletionVerdict.resolve(
            state: .completed(OperationCompletionInfo(success: true, message: "Done")),
            rows: [row("clip.xml", status: "❌ Failed")],
            hasErrors: false,
            hasCriticalErrors: false
        )

        XCTAssertEqual(verdict, .issues)
    }

    func testCriticalDiagnosticResolvesToFailed() {
        let verdict = CompletionVerdict.resolve(
            state: .completed(OperationCompletionInfo(success: true, message: "Done")),
            rows: [row("clip.mov", status: "✅ Verified")],
            hasErrors: true,
            hasCriticalErrors: true
        )

        XCTAssertEqual(verdict, .failed)
    }

    func testFailedOperationStateResolvesToFailed() {
        let verdict = CompletionVerdict.resolve(
            state: .failed,
            rows: [row("clip.mov", status: "✅ Verified")],
            hasErrors: false,
            hasCriticalErrors: false
        )

        XCTAssertEqual(verdict, .failed)
    }

    func testCleanCompletedTrueResolvesToSuccess() {
        let verdict = CompletionVerdict.resolve(
            state: .completed(OperationCompletionInfo(success: true, message: "Done")),
            rows: [row("clip.mov", status: "✅ Verified")],
            hasErrors: false,
            hasCriticalErrors: false
        )

        XCTAssertEqual(verdict, .success)
    }

    func testNoncriticalDiagnosticResolvesToIssues() {
        let verdict = CompletionVerdict.resolve(
            state: .completed(OperationCompletionInfo(success: true, message: "Done")),
            rows: [row("clip.mov", status: "✅ Verified")],
            hasErrors: true,
            hasCriticalErrors: false
        )

        XCTAssertEqual(verdict, .issues)
    }

    func testNonterminalStateCannotResolveToSuccess() {
        let rows = [row("clip.mov", status: "✅ Verified")]

        XCTAssertEqual(
            CompletionVerdict.resolve(
                state: .verifying,
                rows: rows,
                hasErrors: false,
                hasCriticalErrors: false
            ),
            .issues
        )
    }

    func testVisibleRowsCapsMoreThanOneThousandIssuesWithoutTrapping() {
        let rows = (0..<1_001).map { row("\($0).mov", status: "❌ Failed") }

        XCTAssertEqual(
            ResultPresentation.visibleRows(rows, issuesOnly: false, limit: 1_000).count,
            1_000
        )
    }

    func testVisibleRowsFillsRemainingCapacityWithNewestSuccesses() {
        let rows = [
            row("oldest.mov", status: "✅ Verified"),
            row("issue.xml", status: "⚠️ Checksum Mismatch"),
            row("middle.mov", status: "✅ Verified"),
            row("newest.mov", status: "✅ Verified"),
        ]

        let visible = ResultPresentation.visibleRows(rows, issuesOnly: false, limit: 3)

        XCTAssertEqual(visible.map(\.fileName), ["issue.xml", "middle.mov", "newest.mov"])
    }

    func testVisibleRowsHonorsZeroAndNegativeLimits() {
        let rows = [row("clip.mov", status: "❌ Failed")]

        XCTAssertTrue(ResultPresentation.visibleRows(rows, issuesOnly: false, limit: 0).isEmpty)
        XCTAssertTrue(ResultPresentation.visibleRows(rows, issuesOnly: false, limit: -1).isEmpty)
    }

    func testIssuesOnlyFiltersSuccessesBeforeApplyingLimit() {
        let rows = [
            row("clip.mov", status: "✅ Verified"),
            row("one.xml", status: "❌ Failed"),
            row("latest.mov", status: "✅ Verified"),
            row("two.xml", status: "Unknown"),
        ]

        let visible = ResultPresentation.visibleRows(rows, issuesOnly: true, limit: 1)

        XCTAssertEqual(visible.map(\.fileName), ["one.xml"])
        XCTAssertTrue(visible.allSatisfy { !$0.isSuccessStatus })
    }

    private func row(_ fileName: String, status: String) -> ResultRow {
        ResultRow(
            path: "/source/\(fileName)",
            status: status,
            size: 1,
            checksum: nil,
            destination: "RAID"
        )
    }
}
