import Foundation
import Testing
@testable import BitMatch

struct FolderPresetPickerPresentationTests {
    private let defaultRecipe = FolderRecipe.wedding

    private func preset(_ name: String) -> PhotographerPreset {
        PhotographerPreset(
            id: UUID(),
            name: name,
            eventType: .wedding,
            recipe: .wedding,
            requiredLocalCopyCount: 1,
            workflow: .photography
        )
    }

    @Test func defaultRecipeIsAlwaysFirstOption() {
        // Preset names that would sort before "Wedding" must still trail the
        // default: the default is not just another alphabetical preset.
        let presentation = FolderPresetPickerPresentation.make(
            defaultRecipe: defaultRecipe,
            presets: [preset("Aardvark shoot"), preset("Backup style")],
            selectedRecipeID: defaultRecipe.id
        )

        #expect(presentation.options.first?.id == defaultRecipe.id)
        #expect(presentation.options.first?.name == "Wedding")
    }

    @Test func presetOptionsAreAlphabeticalAfterTheDefault() {
        let presentation = FolderPresetPickerPresentation.make(
            defaultRecipe: defaultRecipe,
            presets: [preset("Zeta"), preset("Alpha"), preset("Mid")],
            selectedRecipeID: defaultRecipe.id
        )

        #expect(presentation.options.map(\.name) == ["Wedding", "Alpha", "Mid", "Zeta"])
    }

    @Test func selectedIDPassesThrough() {
        let presetID = UUID()
        let presentation = FolderPresetPickerPresentation.make(
            defaultRecipe: defaultRecipe,
            presets: [PhotographerPreset(id: presetID, name: "Studio", eventType: .portrait, recipe: .wedding, requiredLocalCopyCount: 1, workflow: .photography)],
            selectedRecipeID: presetID
        )

        #expect(presentation.selectedID == presetID)
    }

    @Test func saveDisabledForBlankOrWhitespaceName() {
        #expect(!SavePresetButtonPresentation.make(nameField: "").canSave)
        #expect(!SavePresetButtonPresentation.make(nameField: "   ").canSave)
    }

    @Test func saveEnabledForTrimmedName() {
        #expect(SavePresetButtonPresentation.make(nameField: "  My preset  ").canSave)
    }
}
