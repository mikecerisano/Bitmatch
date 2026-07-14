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

    @Test(arguments: [
        "..",
        "%2e%2e",
        "%252e%252e",
        "../Card-001",
        "%2e%2e%2fCard-001",
        "%252e%252e%252fCard-001",
        "..\\Card-001",
        "foo/../bar",
        "foo\\..\\bar"
    ])
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

    @Test func existingIntermediateSymlinkIsRejectedEvenWhenItStaysInsideDestination() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch_destination_layout_\(UUID().uuidString)")
        let destination = temporaryRoot.appendingPathComponent("SSD")
        let realDirectory = destination.appendingPathComponent("RealJob")
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("Job"),
            withDestinationURL: realDirectory
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "Card-001"]

        expectUnsafeOperation(
            source: temporaryRoot.appendingPathComponent("CARD"),
            destination: destination,
            settings: settings,
            messageContains: "symbolic link"
        )
    }

    @Test func canonicalResolvedRootEscapingDestinationIsRejected() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch_destination_layout_\(UUID().uuidString)")
        let destination = temporaryRoot.appendingPathComponent("SSD")
        let escape = temporaryRoot.appendingPathComponent("Escape")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: escape, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("Job"),
            withDestinationURL: escape
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        var settings = CameraLabelSettings()
        settings.destinationPathComponents = ["Job", "Card-001"]

        expectUnsafeOperation(
            source: temporaryRoot.appendingPathComponent("CARD"),
            destination: destination,
            settings: settings,
            messageContains: "escapes destination root"
        )
    }

    @Test func lateIntermediateSymlinkSubstitutionIsRejectedBeforeCopy() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("bitmatch_late_destination_symlink_\(UUID().uuidString)")
            let source = temporaryRoot.appendingPathComponent("CARD")
            let destination = temporaryRoot.appendingPathComponent("SSD")
            let jobComponent = destination.appendingPathComponent("Job")
            let escape = temporaryRoot.appendingPathComponent("Escape")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: jobComponent, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: escape, withIntermediateDirectories: true)
            try Data("must stay on card".utf8).write(to: source.appendingPathComponent("clip.txt"))
            defer { try? FileManager.default.removeItem(at: temporaryRoot) }

            var settings = CameraLabelSettings()
            settings.destinationPathComponents = ["Job", "Card-001"]
            let fileSystem = LateSymlinkSubstitutionFileSystem(
                component: jobComponent,
                escapeTarget: escape
            )
            let sut = SharedFileOperationsService(
                fileSystem: fileSystem,
                checksum: SharedChecksumService.shared
            )

            do {
                _ = try await sut.performFileOperation(
                    sourceURL: source,
                    destinationURLs: [destination],
                    verificationMode: .quick,
                    settings: settings,
                    estimatedTotalBytes: nil,
                    progressCallback: { _ in },
                    onFileResult: nil
                )
                Issue.record("Expected late destination symlink substitution to fail closed")
            } catch FileOperationError.unsafeOperation(let message) {
                #expect(
                    message.localizedCaseInsensitiveContains("symbolic link") ||
                    message.localizedCaseInsensitiveContains("escapes destination root")
                )
            } catch {
                Issue.record("Expected FileOperationError.unsafeOperation, got \(error)")
            }

            #expect(fileSystem.didSubstitute)
            #expect(FileManager.default.fileExists(
                atPath: escape.appendingPathComponent("Card-001/clip.txt").path
            ) == false)
            #else
            #expect(true)
            #endif
        }
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

#if os(macOS)
private final class LateSymlinkSubstitutionFileSystem: FileSystemService, @unchecked Sendable {
    private let component: URL
    private let escapeTarget: URL
    private let lock = NSLock()
    private var hasSubstituted = false

    init(component: URL, escapeTarget: URL) {
        self.component = component
        self.escapeTarget = escapeTarget
    }

    var didSubstitute: Bool {
        lock.withLock { hasSubstituted }
    }

    func selectSourceFolder() async -> URL? { nil }
    func selectDestinationFolders() async -> [URL] { [] }
    func selectLeftFolder() async -> URL? { nil }
    func selectRightFolder() async -> URL? { nil }
    func validateFileAccess(url: URL) async -> Bool {
        await MacOSFileSystemService.shared.validateFileAccess(url: url)
    }
    func startAccessing(url: URL) -> Bool {
        MacOSFileSystemService.shared.startAccessing(url: url)
    }
    func stopAccessing(url: URL) {
        MacOSFileSystemService.shared.stopAccessing(url: url)
    }
    func getFileList(from folderURL: URL) async throws -> [URL] {
        try await MacOSFileSystemService.shared.getFileList(from: folderURL)
    }
    nonisolated func getFileSize(for url: URL) throws -> Int64 {
        try MacOSFileSystemService.shared.getFileSize(for: url)
    }
    nonisolated func createDirectory(at url: URL) throws {
        try MacOSFileSystemService.shared.createDirectory(at: url)
    }
    nonisolated func freeSpace(at url: URL) -> Int64 {
        substituteOnce()
        return MacOSFileSystemService.shared.freeSpace(at: url)
    }

    private nonisolated func substituteOnce() {
        let shouldSubstitute = lock.withLock {
            guard !hasSubstituted else { return false }
            hasSubstituted = true
            return true
        }
        guard shouldSubstitute else { return }
        try? FileManager.default.removeItem(at: component)
        try? FileManager.default.createSymbolicLink(at: component, withDestinationURL: escapeTarget)
    }
}
#endif
