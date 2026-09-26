import Testing
@testable import BitMatch
import BitMatchEngine

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
