import Foundation

/// Lightweight entry for cached file enumeration (Perf 1)
struct FileEntry: Sendable {
    let url: URL
    let relativePath: String
    let size: Int64
    let modificationDate: Date?

    init(url: URL, relativePath: String, size: Int64, modificationDate: Date? = nil) {
        self.url = url
        self.relativePath = relativePath
        self.size = size
        self.modificationDate = modificationDate
    }
}

enum FileTreeEnumerator {
    /// macOS volume metadata directories written to the root of removable media. They are
    /// not user data and are frequently unreadable without Full Disk Access, so descending
    /// into them would abort the whole transfer with a permission error.
    static let skippedVolumeMetadataDirectories: Set<String> = [
        ".Spotlight-V100",
        ".fseventsd",
        ".Trashes",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
    ]

    /// Perf 1: Enumerate regular files once and cache the list.
    /// Pass result to both copy and verify phases to eliminate triple filesystem walk.
    /// ~20 bytes per entry overhead for 100K files ≈ 20MB - acceptable.
    static func enumerateRegularFiles(base: URL) throws -> [FileEntry] {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let basePath = base.path
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        var entries: [FileEntry] = []
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: base.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw BitMatchError.fileNotFound(base)
        }

        var traversalError: Error?
        guard let enumerator = fileManager.enumerator(
            at: base,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, error in
                if traversalError == nil {
                    traversalError = NSError(
                        domain: "FileTreeEnumerator",
                        code: (error as NSError).code,
                        userInfo: [NSLocalizedDescriptionKey: "Could not read \(url.lastPathComponent): \(error.localizedDescription)"]
                    )
                }
                return false
            }
        ) else {
            throw BitMatchError.fileAccessDenied(base)
        }

        while let item = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try item.resourceValues(forKeys: keys)
            if values.isDirectory == true,
               values.isSymbolicLink != true,
               skippedVolumeMetadataDirectories.contains(item.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true || values.isRegularFile != true {
                continue
            }
            let relativePath = item.path.hasPrefix(basePath + "/")
                ? String(item.path.dropFirst(basePath.count + 1))
                : item.lastPathComponent
            entries.append(FileEntry(
                url: item,
                relativePath: relativePath,
                size: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate
            ))
        }
        if let traversalError { throw traversalError }
        try Task.checkCancellation()
        return entries
    }
}
