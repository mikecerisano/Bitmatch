import Foundation
import Testing
@testable import BitMatch

struct PhotographerDestinationLayoutTests {
    private let source = URL(fileURLWithPath: "/Volumes/CARD")
    private let destination = URL(fileURLWithPath: "/Volumes/SSD")

    @Test func recipeComponentsReplaceLegacyCardFolder() throws {
        var settings = CameraLabelSettings()
        settings.destinationPathComponents = [
            "2026-07-13_Smith-Wedding", "Originals", "Mike", "Sony-A7-IV", "Card-001"
        ]

        let root = SafetyValidator.resolvedDestinationRoot(
            source: source,
            destination: destination,
            settings: settings
        )

        #expect(root.path == "/Volumes/SSD/2026-07-13_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001")
    }

    @Test func resolverThreadsRenderedRecipeWithoutChangingBaseSettings() {
        var base = CameraLabelSettings()
        base.label = "Legacy Label"
        base.groupByCamera = true
        let rendered = RenderedFolderRecipe(components: ["Job", "Originals", "Card-001"])

        let resolved = PhotographerDestinationResolver.operationSettings(
            base: base,
            renderedRecipe: rendered
        )

        #expect(resolved.destinationPathComponents == rendered.components)
        #expect(resolved.label == base.label)
        #expect(resolved.groupByCamera == base.groupByCamera)
        #expect(base.destinationPathComponents == nil)
    }

    @Test func componentsAreSanitizedIndividually() throws {
        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Smith/Wedding", "Mike\\Sony", "Card-001"]

        let root = try SafetyValidator.resolvedDestinationRootChecked(
            source: source,
            destination: destination,
            settings: settings
        )

        #expect(root.path == "/Volumes/SSD/Smith_Wedding/Mike_Sony/Card-001")
    }

    @Test(arguments: ["..", "%2e%2e", "%252e%252e"])
    func traversalComponentsAreRejected(component: String) {
        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", component, "Card-001"]

        expectUnsafeOperation(
            source: source,
            destination: destination,
            settings: settings,
            messageContains: "invalid destination path component"
        )
    }

    @Test(arguments: [[], [""], ["  "], ["\n\t"]])
    func emptyComponentsAreRejected(components: [String]) {
        var settings = CameraLabelSettings()
        settings.destinationPathComponents = components

        expectUnsafeOperation(
            source: source,
            destination: destination,
            settings: settings,
            messageContains: "destination path component"
        )
    }

    @Test func explicitUntitledComponentIsAllowed() throws {
        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "untitled", "Card-001"]

        let root = try SafetyValidator.resolvedDestinationRootChecked(
            source: source,
            destination: destination,
            settings: settings
        )

        #expect(root.path == "/Volumes/SSD/Job/untitled/Card-001")
    }

    @Test func nilComponentsPreserveLegacyCameraLabelBehavior() {
        var settings = CameraLabelSettings()
        settings.label = "A Cam"

        let root = SafetyValidator.resolvedDestinationRoot(
            source: source,
            destination: destination,
            settings: settings
        )

        #expect(root.path == "/Volumes/SSD/A Cam_CARD")
    }

    @Test func nilComponentsPreserveLegacyCameraGroupingBehavior() {
        var settings = CameraLabelSettings()
        settings.label = "A Cam"
        settings.groupByCamera = true

        let root = SafetyValidator.resolvedDestinationRoot(
            source: source,
            destination: destination,
            settings: settings
        )

        #expect(root.path == "/Volumes/SSD/A Cam/CARD")
    }

    @Test func resolvedRootOverlappingSourceIsRejected() {
        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "Card-001"]

        expectUnsafeOperation(
            source: URL(fileURLWithPath: "/Volumes/SSD/Job/Card-001"),
            destination: destination,
            settings: settings,
            messageContains: "Destination is the source folder"
        )
    }

    @Test func existingFileAtResolvedRootIsRejected() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch_destination_layout_\(UUID().uuidString)")
        let source = temporaryRoot.appendingPathComponent("CARD")
        let destination = temporaryRoot.appendingPathComponent("SSD")
        let conflictingRoot = destination.appendingPathComponent("Job/Card-001")
        try FileManager.default.createDirectory(
            at: conflictingRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("existing".utf8).write(to: conflictingRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "Card-001"]

        expectUnsafeOperation(
            source: source,
            destination: destination,
            settings: settings,
            messageContains: "already exists and is not a folder"
        )
    }

    @Test func existingFileAtIntermediateComponentIsRejected() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch_destination_layout_\(UUID().uuidString)")
        let source = temporaryRoot.appendingPathComponent("CARD")
        let destination = temporaryRoot.appendingPathComponent("SSD")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destination.appendingPathComponent("Job"))
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "Card-001"]

        expectUnsafeOperation(
            source: source,
            destination: destination,
            settings: settings,
            messageContains: "already exists and is not a folder"
        )
    }

    @Test func nonthrowingResolutionKeepsPlannedRootWhenConflictAppears() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch_destination_layout_\(UUID().uuidString)")
        let source = temporaryRoot.appendingPathComponent("CARD")
        let destination = temporaryRoot.appendingPathComponent("SSD")
        let conflictingRoot = destination.appendingPathComponent("Job/Card-001")
        try FileManager.default.createDirectory(
            at: conflictingRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("late conflict".utf8).write(to: conflictingRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "Card-001"]

        let resolved = SafetyValidator.resolvedDestinationRoot(
            source: source,
            destination: destination,
            settings: settings
        )

        #expect(resolved == conflictingRoot)
    }

    private func expectUnsafeOperation(
        source: URL,
        destination: URL,
        settings: CameraLabelSettings,
        messageContains expectedText: String
    ) {
        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: source,
                destinations: [destination],
                settings: settings
            )
            Issue.record("Expected FileOperationError.unsafeOperation")
        } catch FileOperationError.unsafeOperation(let message) {
            #expect(message.localizedCaseInsensitiveContains(expectedText))
        } catch {
            Issue.record("Expected FileOperationError.unsafeOperation, got \(error)")
        }
    }
}
