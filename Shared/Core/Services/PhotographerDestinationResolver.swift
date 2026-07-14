enum PhotographerDestinationResolver {
    static func operationSettings(
        base: CameraLabelSettings,
        renderedRecipe: RenderedFolderRecipe
    ) -> CameraLabelSettings {
        var value = base
        value.destinationPathComponents = renderedRecipe.components
        return value
    }
}
