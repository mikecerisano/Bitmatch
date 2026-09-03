// Shared/Core/Services/File/SafetyValidator.swift
// Moved to Shared module to enable iOS safety validation
import Foundation

/// Validates file operations for safety before execution
/// Used by both macOS and iOS to prevent dangerous operations
final class SafetyValidator {

    // MARK: - Pre-Operation Safety Checks

    static func performSafetyChecks(
        source: URL,
        destinations: [URL],
        sourceSizeBytes: Int64
    ) async throws {
        // Validate source exists and is accessible
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FileOperationError.sourceNotFound(source.path)
        }

        // Check source is a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileOperationError.sourceNotDirectory(source.path)
        }

        try validateSourceTreeForCopy(source: source)

        let uniqueDestinationPaths = Set(destinations.map { canonicalPath($0) })
        guard uniqueDestinationPaths.count == destinations.count else {
            throw FileOperationError.unsafeOperation("Destination folders must be unique")
        }

        // Check each destination
        for destination in destinations {
            try await validateDestination(destination, source: source)
        }

        // Check for sufficient space
        try await validateAvailableSpace(sourceSizeBytes: sourceSizeBytes, destinations: destinations)

        SharedLogger.info("Safety checks passed for \(destinations.count) destinations", category: .transfer)
    }

    static func performComparisonChecks(left: URL, right: URL) async throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: left.path) else {
            throw FileOperationError.sourceNotFound(left.path)
        }

        guard fm.fileExists(atPath: right.path) else {
            throw FileOperationError.sourceNotFound(right.path)
        }

        guard !detectSymlinkLoop(at: left) else {
            throw FileOperationError.symlinkLoop(left.path)
        }
        guard !detectSymlinkLoop(at: right) else {
            throw FileOperationError.symlinkLoop(right.path)
        }

        SharedLogger.info("Comparison safety checks passed", category: .transfer)
    }

    private static func validateDestination(_ destination: URL, source: URL) async throws {
        let fm = FileManager.default

        if isProtectedSystemPath(destination) {
            throw FileOperationError.unsafeOperation("System folders cannot be used as destinations")
        }

        if let safetyIssue = destinationSafetyIssue(source: source, destination: destination) {
            throw FileOperationError.unsafeOperation(safetyIssue)
        }

        // The destination is a user-selected existing folder. Requiring it to
        // exist prevents path-based creation before the later descriptor pin.
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileOperationError.destinationNotWritable(destination.path)
        }

        // Verify it's accessible
        guard fm.isWritableFile(atPath: destination.path) else {
            throw FileOperationError.destinationNotWritable(destination.path)
        }

        // Check for symlink loops
        guard !detectSymlinkLoop(at: source) else {
            throw FileOperationError.symlinkLoop(source.path)
        }

        // Network drive warning
        if isNetworkVolume(destination) {
            SharedLogger.warning("Network destination detected: \(destination.lastPathComponent) - may be slower", category: .transfer)
        }
    }

    private static func validateAvailableSpace(sourceSizeBytes: Int64, destinations: [URL]) async throws {
        let requiredSpace = try checkedRequiredSpace(
            sourceBytes: sourceSizeBytes,
            headroomBytes: 1_000_000_000
        )

        for destination in destinations {
            let availableSpace = getAvailableSpace(at: destination)

            guard availableSpace > requiredSpace else {
                let availableGB = Double(availableSpace) / 1_000_000_000
                let requiredGB = Double(requiredSpace) / 1_000_000_000
                throw FileOperationError.insufficientSpace(
                    destination.path,
                    available: availableGB,
                    required: requiredGB
                )
            }
        }
    }

    // MARK: - Network Drive Detection

    static func isNetworkVolume(_ url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRemovableKey])
            return !(resourceValues.volumeIsLocal ?? true)
        } catch {
            return false
        }
    }

    // MARK: - Symlink Loop Detection

    private static func detectSymlinkLoop(at url: URL, visited: Set<URL> = []) -> Bool {
        guard visited.count < 100 else { return true } // Prevent infinite recursion

        var newVisited = visited
        newVisited.insert(url)

        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                let resolved = try URL(resolvingAliasFileAt: url)
                return newVisited.contains(resolved) || detectSymlinkLoop(at: resolved, visited: newVisited)
            }
        } catch {
            return false
        }

        return false
    }

    // MARK: - Path Safety

    static func destinationSafetyIssue(source: URL, destination: URL) -> String? {
        let sourcePath = canonicalPath(source)
        let destPath = canonicalPath(destination)

        // Don't copy to self
        if sourcePath == destPath {
            return "Destination is the source folder"
        }

        // Don't copy into the source tree. This can recursively grow the transfer.
        if pathIsWithin(destPath, root: sourcePath) {
            return "Destination is inside the source folder"
        }

        // Don't use a parent of the source as the destination root. BitMatch writes
        // into destination/sourceName, which can collide with the original source.
        if pathIsWithin(sourcePath, root: destPath) {
            return "Destination contains the source folder"
        }

        return nil
    }

    static func resolvedDestinationRoot(source: URL, destination: URL, settings: CameraLabelSettings) -> URL {
        return destinationRootComponents(source: source, settings: settings).reduce(destination) { root, component in
            root.appendingPathComponent(component)
        }
    }

    /// The exact relative layout used below every selected destination. Keeping
    /// this separate from URL resolution lets descriptor-pinned writes preserve
    /// legacy camera-grouping behavior without re-resolving a pathname later.
    static func destinationRootComponents(source: URL, settings: CameraLabelSettings) -> [String] {
        if let components = settings.destinationPathComponents {
            return components.map(CameraLabelSettings.sanitizePathComponent)
        }

        let cardName = source.lastPathComponent
        if settings.groupByCamera {
            let raw = settings.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = raw.isEmpty ? "Camera" : CameraLabelSettings.sanitizePathComponent(raw)
            return [group, cardName]
        }

        let labeledCardName = settings.formattedFolderName(for: cardName)
        return [labeledCardName.isEmpty ? cardName : labeledCardName]
    }

    static func resolvedDestinationRootChecked(
        source: URL,
        destination: URL,
        settings: CameraLabelSettings
    ) throws -> URL {
        guard let components = settings.destinationPathComponents else {
            return resolvedDestinationRoot(source: source, destination: destination, settings: settings)
        }

        guard !components.isEmpty else {
            throw FileOperationError.unsafeOperation("Destination path components cannot be empty")
        }

        var root = destination
        var firstSymbolicLink: URL?
        for (index, component) in components.enumerated() {
            guard !containsTraversalComponent(component) else {
                throw FileOperationError.unsafeOperation(
                    "Invalid destination path component at index \(index)"
                )
            }

            let sanitized = CameraLabelSettings.sanitizePathComponent(component)
            guard sanitized != "untitled" || component == "untitled" else {
                throw FileOperationError.unsafeOperation(
                    "Invalid destination path component at index \(index)"
                )
            }

            let nextRoot = root.appendingPathComponent(sanitized)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: nextRoot.path)) != nil,
               firstSymbolicLink == nil {
                firstSymbolicLink = nextRoot
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: nextRoot.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                throw FileOperationError.unsafeOperation(
                    "\(nextRoot.lastPathComponent) already exists and is not a folder"
                )
            }
            root = nextRoot
        }

        guard destinationRootIsContained(root, within: destination) else {
            throw FileOperationError.unsafeOperation("Resolved destination root escapes destination root")
        }
        if let firstSymbolicLink {
            throw FileOperationError.unsafeOperation(
                "\(firstSymbolicLink.lastPathComponent) is a symbolic link"
            )
        }
        return root
    }

    private static func containsTraversalComponent(_ component: String) -> Bool {
        var decoded = component
        var iterations = 0
        while let next = decoded.removingPercentEncoding,
              next != decoded,
              iterations < 5 {
            decoded = next
            iterations += 1
        }

        return decoded
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains { segment in
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed == "." || trimmed == ".."
            }
    }

    private static func destinationRootIsContained(_ root: URL, within destination: URL) -> Bool {
        let standardizedRoot = root.standardizedFileURL.path
        let standardizedDestination = destination.standardizedFileURL.path
        guard pathIsStrictlyWithin(standardizedRoot, root: standardizedDestination) else {
            return false
        }

        let canonicalRoot = canonicalPathResolvingExistingPrefixes(root)
        let canonicalDestination = canonicalPathResolvingExistingPrefixes(destination)
        return pathIsStrictlyWithin(canonicalRoot, root: canonicalDestination)
    }

    private static func canonicalPathResolvingExistingPrefixes(_ url: URL) -> String {
        var resolved = URL(fileURLWithPath: "/", isDirectory: true)

        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            let candidate = resolved.appendingPathComponent(component)
            guard let linkDestination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: candidate.path
            ) else {
                resolved = candidate
                continue
            }

            let target: URL
            if linkDestination.hasPrefix("/") {
                target = URL(fileURLWithPath: linkDestination)
            } else {
                target = candidate.deletingLastPathComponent().appendingPathComponent(linkDestination)
            }
            resolved = target.standardizedFileURL.resolvingSymlinksInPath()
        }

        return resolved.standardizedFileURL.path
    }

    static func validateResolvedDestinationRoots(source: URL, destinations: [URL], settings: CameraLabelSettings) throws {
        let roots = try destinations.map {
            try resolvedDestinationRootChecked(source: source, destination: $0, settings: settings)
        }
        let rootPaths = roots.map { canonicalPath($0) }

        guard Set(rootPaths).count == rootPaths.count else {
            throw FileOperationError.unsafeOperation("Resolved destination folders must be unique")
        }

        for root in roots {
            if let issue = destinationSafetyIssue(source: source, destination: root) {
                throw FileOperationError.unsafeOperation("\(root.lastPathComponent): \(issue)")
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                throw FileOperationError.unsafeOperation("\(root.lastPathComponent) already exists and is not a folder")
            }

            if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw FileOperationError.unsafeOperation("\(root.lastPathComponent) is a symbolic link")
            }
        }

        for (index, path) in rootPaths.enumerated() {
            for (otherIndex, otherPath) in rootPaths.enumerated() where index != otherIndex {
                if pathIsWithin(path, root: otherPath) {
                    throw FileOperationError.unsafeOperation("Resolved destination folders cannot be nested inside each other")
                }
            }
        }
    }

    static func validateSourceTreeForCopy(source: URL) throws {
        let fm = FileManager.default
        let resolver = RelativePathResolver(base: source)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var relativePaths: [String] = []

        guard let enumerator = fm.enumerator(
            at: source,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return }

        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                continue
            }
            guard values.isRegularFile == true || values.isDirectory == true else {
                continue
            }

            relativePaths.append(try resolver.resolve(item))
        }

        try validatePortableRelativePaths(relativePaths)
    }

    static func validatePortableRelativePaths(_ relativePaths: [String]) throws {
        let locale = Locale(identifier: "en_US_POSIX")
        var seen: [String: String] = [:]

        for relativePath in relativePaths {
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            if components.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) {
                throw FileOperationError.unsafeOperation("Source contains an unsafe relative path: \(relativePath)")
            }

            let portableKey = relativePath
                .precomposedStringWithCanonicalMapping
                .lowercased(with: locale)

            if let original = seen[portableKey], original != relativePath {
                throw FileOperationError.unsafeOperation(
                    "Source contains paths that collide on case-insensitive filesystems: \(original) and \(relativePath)"
                )
            }
            seen[portableKey] = relativePath
        }
    }

    // MARK: - Utility Functions

    private static func getAvailableSpace(at url: URL) -> Int64 {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
            ])
            return resolvedAvailableSpace(
                importantUsage: resourceValues.volumeAvailableCapacityForImportantUsage,
                standardCapacity: resourceValues.volumeAvailableCapacity
            )
        } catch {
            return 0
        }
    }

    /// `volumeAvailableCapacityForImportantUsage` is only meaningful on APFS. On exFAT/FAT
    /// (typical external SSDs and camera cards) macOS reports it as 0, not nil, so a
    /// non-positive value must fall back to the standard capacity.
    static func resolvedAvailableSpace(
        importantUsage: Int64?,
        standardCapacity: Int?
    ) -> Int64 {
        if let importantUsage, importantUsage > 0 {
            return importantUsage
        }
        return Int64(standardCapacity ?? 0)
    }

    static func checkedRequiredSpace(sourceBytes: Int64, headroomBytes: Int64) throws -> Int64 {
        guard sourceBytes >= 0, headroomBytes >= 0 else {
            throw FileOperationError.unsafeOperation("Source size exceeds the supported range")
        }
        let (requiredSpace, overflow) = sourceBytes.addingReportingOverflow(headroomBytes)
        guard !overflow else {
            throw FileOperationError.unsafeOperation("Source size exceeds the supported range")
        }
        return requiredSpace
    }

    private static let protectedSystemPrefixes: [String] = [
        "/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/var"
    ]

    static func isProtectedSystemPath(_ url: URL) -> Bool {
        let path = canonicalPath(url)
        let temporaryPath = canonicalPath(FileManager.default.temporaryDirectory)
        if pathIsWithin(path, root: temporaryPath) {
            return false
        }
        return protectedSystemPrefixes.contains { path == $0 || pathIsWithin(path, root: $0) }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Compare path-components, not raw prefixes, to avoid boundary bypasses.
    private static func pathIsWithin(_ candidatePath: String, root rootPath: String) -> Bool {
        let candidateComponents = URL(fileURLWithPath: candidatePath).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: rootPath).standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy(==)
    }

    private static func pathIsStrictlyWithin(_ candidatePath: String, root rootPath: String) -> Bool {
        let candidateComponents = URL(fileURLWithPath: candidatePath).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: rootPath).standardizedFileURL.pathComponents
        guard candidateComponents.count > rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy(==)
    }
}

// MARK: - Error Types

enum FileOperationError: LocalizedError, Equatable {
    case operationAlreadyInProgress
    case sourceNotFound(String)
    case sourceNotDirectory(String)
    case destinationNotWritable(String)
    case unsafeOperation(String)
    case symlinkLoop(String)
    case insufficientSpace(String, available: Double, required: Double)

    var errorDescription: String? {
        switch self {
        case .operationAlreadyInProgress:
            return "Another file operation is already active or cancelling."
        case .sourceNotFound(_):
            return "Source folder not found"
        case .sourceNotDirectory(_):
            return "Source is not a directory"
        case .destinationNotWritable(_):
            return "Cannot write to destination"
        case .unsafeOperation(let message):
            return "Unsafe operation: \(message)"
        case .symlinkLoop(_):
            return "Symlink loop detected"
        case .insufficientSpace(_, let available, let required):
            return "Insufficient space: \(String(format: "%.1f", available))GB available, \(String(format: "%.1f", required))GB required"
        }
    }
}
