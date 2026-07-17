import Testing
@testable import BitMatch

struct MasterReportLayoutPolicyTests {
    @Test func reportSummaryUsesAGridBeforeStatsBecomeCrowded() {
        #expect(MasterReportLayoutPolicy.presentation(for: 639) == .compactGrid)
        #expect(MasterReportLayoutPolicy.presentation(for: 640) == .horizontal)
    }
}
