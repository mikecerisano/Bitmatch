import Testing
@testable import BitMatch

struct ResultTableLayoutPolicyTests {
    @Test func resultRowsCollapseSecondaryColumnsOnCompactWindows() {
        #expect(ResultTableLayoutPolicy.presentation(for: 699) == .compact)
        #expect(ResultTableLayoutPolicy.presentation(for: 700) == .detailed)
    }
}
