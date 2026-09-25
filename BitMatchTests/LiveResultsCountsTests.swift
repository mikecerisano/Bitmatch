// LiveResultsCountsTests.swift
// The Mac live results header and its "no issues" message read a counter
// that was never incremented (always "0", and "All N files verified" could
// never show). Counts now come from the rows themselves.
import Foundation
import Testing
@testable import BitMatch

struct LiveResultsCountsTests {
    private func row(_ outcome: ResultOutcome) -> ResultRow {
        ResultRow(path: "/c/\(UUID().uuidString)", status: outcome.statusText, size: 1, checksum: nil, destination: "B")
    }

    /// Fails if `LiveResultsCounts.make` counts copied rows as verified.
    @Test func countsComeFromTheRows() {
        let counts = LiveResultsCounts.make(rows: [row(.verified), row(.verified), row(.copiedUnverified), row(.failed)])
        #expect(counts.verified == 2)
        #expect(counts.copiedNotVerified == 1)
        #expect(counts.issues == 1)
    }

    /// "All N verified" only when every row is verified; a Quick run says
    /// what happened instead. Fails if the all-verified message ignores
    /// unverified rows.
    @Test func noIssuesMessageSaysWhatWasChecked() {
        #expect(LiveResultsCounts.make(rows: [row(.verified), row(.verified)]).noIssuesMessage == "All 2 files verified")
        #expect(LiveResultsCounts.make(rows: [row(.copiedUnverified), row(.copiedUnverified)]).noIssuesMessage == "2 files copied, not verified")
        #expect(LiveResultsCounts.make(rows: [row(.verified), row(.copiedUnverified)]).noIssuesMessage == "1 verified, 1 copied but not verified")
        #expect(LiveResultsCounts.make(rows: []).noIssuesMessage == nil)
    }
}
