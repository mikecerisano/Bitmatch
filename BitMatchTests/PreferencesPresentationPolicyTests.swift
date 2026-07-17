import Testing
@testable import BitMatch

struct PreferencesPresentationPolicyTests {
    @Test func destinationsSettingsCanExpandWhenTheirContentNeedsRoom() {
        #expect(PreferencesPresentationPolicy.allowsManualResizing)
        #expect(PreferencesPresentationPolicy.minimumWidth >= 580)
    }
}
