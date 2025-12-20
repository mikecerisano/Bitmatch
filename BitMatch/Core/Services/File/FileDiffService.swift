import Foundation

enum FileDiffService {
    /// Detect extra files present in destination that are not in source and report them in batches via onProgress.
    static func checkForExtraFiles(
        in destination: URL,
        comparedTo source: URL,
        onProgress: @escaping ([ResultRow]) -> Void
    ) async throws {
        // Collect source file relative paths
        let sourceFiles = await FileTreeEnumeratorPaths.collectRelativePaths(at: source, relativeTo: source)

        // Walk destination and find extras
        var extraRows: [ResultRow] = []
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: destination, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                do {
                    if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        let relative = String(url.path.dropFirst(destination.path.count + 1))
                        if !sourceFiles.contains(relative) {
                            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                            extraRows.append(ResultRow(path: relative, status: "Extra in Destination", size: size, checksum: nil, destination: nil))
                            if extraRows.count >= 50 {
                                onProgress(extraRows)
                                extraRows.removeAll(keepingCapacity: true)
                            }
                        }
                    }
                } catch {
                    // Ignore and keep scanning
                }
            }
        }

        if !extraRows.isEmpty { onProgress(extraRows) }
    }
}

/// Helper to collect relative path sets efficiently.
enum FileTreeEnumeratorPaths {
    static func collectRelativePaths(at url: URL, relativeTo base: URL) async -> Set<String> {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                var paths = Set<String>()
                let fm = FileManager.default
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    while let u = enumerator.nextObject() as? URL {
                        if let isFile = try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true {
                            let rel = String(u.path.dropFirst(base.path.count + 1))
                            paths.insert(rel)
                        }
                    }
                }
                continuation.resume(returning: paths)
            }
        }
    }
}
