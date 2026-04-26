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
    static func enumerateRegularFiles(base: URL) -> [FileEntry] {
        var entries: [FileEntry] = []
        let fm = FileManager.default
        let basePath = base.path
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        if let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) {
            while let item = enumerator.nextObject() as? URL {
                if Task.isCancelled { return entries }
                guard let rv = try? item.resourceValues(forKeys: keys) else { continue }
                if rv.isSymbolicLink == true { continue }
                if rv.isRegularFile == true {
                    let filePath = item.path
                    let relative: String
                    if filePath.hasPrefix(basePath + "/") {
                        relative = String(filePath.dropFirst(basePath.count + 1))
                    } else {
                        relative = item.lastPathComponent
                    }
                    entries.append(FileEntry(
                        url: item,
                        relativePath: relative,
                        size: Int64(rv.fileSize ?? 0)
                    ))
                }
            }
        }
        return entries
    }

    static func countRegularFiles(base: URL) -> Int {
        var count = 0
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        if let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) {
            while let item = enumerator.nextObject() as? URL {
                if Task.isCancelled { return count }
                guard let values = try? item.resourceValues(forKeys: keys) else { continue }
                if values.isSymbolicLink != true && values.isRegularFile == true {
                    count += 1
                }
            }
        }
        return count
    }
}
