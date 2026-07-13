import Foundation

/// Lightweight entry for cached file enumeration (Perf 1)
struct FileEntry {
    let url: URL
    let relativePath: String
    let size: Int64
}

enum FileTreeEnumerator {
    /// Perf 1: Enumerate regular files once and cache the list.
    /// Pass result to both copy and verify phases to eliminate triple filesystem walk.
    /// ~20 bytes per entry overhead for 100K files ≈ 20MB - acceptable.
    static func enumerateRegularFiles(base: URL) throws -> [FileEntry] {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let basePath = base.path
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
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
            if values.isSymbolicLink == true || values.isRegularFile != true {
                continue
            }
            let relativePath = item.path.hasPrefix(basePath + "/")
                ? String(item.path.dropFirst(basePath.count + 1))
                : item.lastPathComponent
            entries.append(FileEntry(
                url: item,
                relativePath: relativePath,
                size: Int64(values.fileSize ?? 0)
            ))
        }
        if let traversalError { throw traversalError }
        try Task.checkCancellation()
        return entries
    }
}
