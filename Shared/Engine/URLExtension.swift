import Foundation

public extension URL {
    public func relativePath(to base: URL) -> String {
        let base = base.standardizedFileURL.resolvingSymlinksInPath()
        let me = self.standardizedFileURL.resolvingSymlinksInPath()
        let a = base.pathComponents
        let b = me.pathComponents
        guard b.starts(with: a) else { return self.lastPathComponent }
        return b.dropFirst(a.count).joined(separator: "/")
    }

    public func isAncestor(of other: URL) -> Bool {
        let a = standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let b = other.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return b.starts(with: a)
    }

    public func nonConflictingSibling(maxAttempts: Int = 9_999) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return self }

        let directory = deletingLastPathComponent()
        let baseName = deletingPathExtension().lastPathComponent
        let ext = pathExtension

        for index in 2...maxAttempts {
            var candidate = directory.appendingPathComponent("\(baseName)-\(index)")
            if !ext.isEmpty {
                candidate = candidate.appendingPathExtension(ext)
            }
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        var fallback = directory.appendingPathComponent("\(baseName)-\(UUID().uuidString)")
        if !ext.isEmpty {
            fallback = fallback.appendingPathExtension(ext)
        }
        return fallback
    }
}
