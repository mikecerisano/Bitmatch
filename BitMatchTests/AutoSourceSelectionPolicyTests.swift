import Testing
@testable import BitMatch

struct AutoSourceSelectionPolicyTests {
    @Test func automaticSourceSelectionStartsDisabled() {
        #expect(ReportPrefs().autoPopulateSource == false)
    }

    @Test func inaccessibleCardIsNeverAutomaticallySelected() {
        #expect(!AutomaticSourceSelectionPolicy.shouldSelect(
            automaticSelectionEnabled: true,
            hasExistingSource: false,
            isReadable: false
        ))
    }
}
