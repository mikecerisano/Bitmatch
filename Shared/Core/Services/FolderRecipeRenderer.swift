import Foundation

enum FolderRecipeRenderer {
    static func render(_ recipe: FolderRecipe, context: FolderRecipeContext) throws -> RenderedFolderRecipe {
        guard context.cardNumber > 0 else { throw FolderRecipeError.invalidCardNumber }
        var components: [String] = []
        for layer in recipe.layers where layer.isEnabled {
            let raw: String
            switch layer.kind {
            case .dateAndJob:
                let jobName = try required(context.jobName, "job name").replacingOccurrences(of: " ", with: "-")
                raw = "\(dateFormatter.string(from: context.eventDate))_\(jobName)"
            case .originals: raw = "Originals"
            case .photographer: raw = try required(context.photographer, "photographer")
            case .camera: raw = try required(context.camera, "camera").replacingOccurrences(of: " ", with: "-")
            case .cardNumber: raw = String(format: "Card-%03d", context.cardNumber)
            }
            components.append(CameraLabelSettings.sanitizePathComponent(raw))
        }
        guard !components.isEmpty else { throw FolderRecipeError.missingRequiredValue("folder layers") }
        return RenderedFolderRecipe(components: components)
    }

    private static let dateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static func required(_ value: String, _ label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderRecipeError.missingRequiredValue(label) }
        return trimmed
    }
}
