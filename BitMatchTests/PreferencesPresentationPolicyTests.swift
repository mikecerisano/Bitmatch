import Testing
@testable import BitMatch

struct PreferencesPresentationPolicyTests {
    @Test func destinationsSettingsCanExpandWhenTheirContentNeedsRoom() {
        #expect(PreferencesPresentationPolicy.allowsManualResizing)
        #expect(PreferencesPresentationPolicy.minimumWidth >= 580)
    }

    /// Guards the tab hit-area bug: PreferencesWindow pairs this frame with
    /// `.contentShape(Rectangle())` so the whole tab, not just its icon and
    /// label glyphs, is clickable. A zero or negative size here would shrink
    /// the clickable frame back down to nothing. Planted `tabWidth = 0` and
    /// `tabHeight = 0`: this test failed as expected; reverted.
    @Test func tabClickTargetsHaveRealSize() {
        #expect(PreferencesPresentationPolicy.tabWidth > 0)
        #expect(PreferencesPresentationPolicy.tabHeight > 0)
    }

    /// Guards the uneven-icon-height bug: every tab icon renders inside a
    /// fixed square well so gear/drive/doc/camera glyphs (which differ in
    /// natural height) share one baseline. Planted `tabIconWellSize = 0`:
    /// this test failed as expected; reverted.
    @Test func tabIconsShareAFixedWellSoTheyAlign() {
        #expect(PreferencesPresentationPolicy.tabIconWellSize > 0)
        // The well must fit inside the tab without crowding the caption below it.
        #expect(PreferencesPresentationPolicy.tabIconWellSize < PreferencesPresentationPolicy.tabHeight)
    }
}
