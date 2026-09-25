import Foundation

/// One row in the folder-preset picker: a workflow's built-in default, or a
/// saved `PhotographerPreset`. Shared by every platform (UI plan step 4.8,
/// wave 2), so presets are creatable, chosen and applied the same way on
/// Mac, iPad and iPhone.
struct FolderPresetOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}

/// The folder-preset picker's options and selection, derived the same way
/// on every platform. The workflow's built-in recipe is always first and
/// never resorted with the saved presets, so it reads as "the default", not
/// as one preset among others; saved presets follow, alphabetically.
struct FolderPresetPickerPresentation: Equatable, Sendable {
    let options: [FolderPresetOption]
    let selectedID: UUID

    static func make(
        defaultRecipe: FolderRecipe,
        presets: [PhotographerPreset],
        selectedRecipeID: UUID
    ) -> Self {
        let defaultOption = FolderPresetOption(id: defaultRecipe.id, name: defaultRecipe.name)
        let presetOptions = presets
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { FolderPresetOption(id: $0.id, name: $0.name) }
        return Self(options: [defaultOption] + presetOptions, selectedID: selectedRecipeID)
    }
}

/// Whether "Save as preset" may be pressed: the same rule everywhere, a
/// non-blank name once whitespace is trimmed.
struct SavePresetButtonPresentation: Equatable, Sendable {
    let canSave: Bool

    static func make(nameField: String) -> Self {
        Self(canSave: !nameField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
