import Foundation
import Testing
@testable import BitMatch_iPad

/// Guards that presets are creatable, chosen and applied the same way on
/// iPad and iPhone as on the Mac (UI plan step 4.8, wave 2). Before this
/// change, iOS's project setup card had no preset picker at all, so this
/// test would have had nothing to call.
struct FolderPresetPickerPresentationIOSTests {
    @Test func presetPickerOffersTheDefaultEvenWithNoSavedPresets() {
        let presentation = FolderPresetPickerPresentation.make(
            defaultRecipe: .wedding,
            presets: [],
            selectedRecipeID: FolderRecipe.wedding.id
        )

        #expect(presentation.options.map(\.name) == ["Wedding"])
    }

    @Test func presetPickerIncludesSavedPresetsOnIOS() {
        let preset = PhotographerPreset(
            id: UUID(),
            name: "Studio wedding",
            eventType: .wedding,
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            workflow: .photography
        )

        let presentation = FolderPresetPickerPresentation.make(
            defaultRecipe: .wedding,
            presets: [preset],
            selectedRecipeID: preset.id
        )

        #expect(presentation.options.map(\.name) == ["Wedding", "Studio wedding"])
        #expect(presentation.selectedID == preset.id)
    }
}
