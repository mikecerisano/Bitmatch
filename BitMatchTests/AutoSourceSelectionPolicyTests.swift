import Testing
@testable import BitMatch
import BitMatchEngine

struct AutoSourceSelectionPolicyTests {
    /// On by default (2026-09-26): it only fills an empty source with a
    /// readable detected card and never starts a transfer.
    @Test func automaticSourceSelectionStartsEnabled() {
        #expect(ReportPrefs().autoPopulateSource == true)
    }

    @Test func inaccessibleCardIsNeverAutomaticallySelected() {
        #expect(!AutomaticSourceSelectionPolicy.shouldSelect(
            automaticSelectionEnabled: true,
            hasExistingSource: false,
            isReadable: false
        ))
    }
}
