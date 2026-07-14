import Foundation
import Testing
@testable import BitMatch

struct FolderRecipeRendererTests {
    private let context = FolderRecipeContext(
        eventDate: Date(timeIntervalSince1970: 1_783_915_200),
        jobName: "Smith Wedding",
        photographer: "Mike",
        camera: "Sony A7 IV",
        cardNumber: 1
    )

    @Test func weddingPresetRendersExpectedComponents() throws {
        let rendered = try FolderRecipeRenderer.render(.wedding, context: context)
        #expect(rendered.components == [
            "2026-07-13_Smith-Wedding", "Originals", "Mike", "Sony-A7-IV", "Card-001"
        ])
    }

    @Test func disabledLayerIsOmittedWithoutChangingCardContents() throws {
        var recipe = FolderRecipe.wedding
        recipe.layers[2].isEnabled = false
        let rendered = try FolderRecipeRenderer.render(recipe, context: context)
        #expect(!rendered.components.contains("Mike"))
        #expect(rendered.components.last == "Card-001")
    }

    @Test func emptyJobNameFailsClosed() {
        let invalid = FolderRecipeContext(
            eventDate: context.eventDate,
            jobName: "  ",
            photographer: "Mike",
            camera: "Sony A7 IV",
            cardNumber: 1
        )
        #expect(throws: FolderRecipeError.self) {
            try FolderRecipeRenderer.render(.wedding, context: invalid)
        }
    }
}
