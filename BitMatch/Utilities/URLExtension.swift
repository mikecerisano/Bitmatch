import Foundation

extension URL {
    func relativePath(to base: URL) -> String {
        let base = base.standardizedFileURL.resolvingSymlinksInPath()
        let me = self.standardizedFileURL.resolvingSymlinksInPath()
        let a = base.pathComponents
        let b = me.pathComponents
        guard b.starts(with: a) else { return self.lastPathComponent }
        return b.dropFirst(a.count).joined(separator: "/")
    }

    func isAncestor(of other: URL) -> Bool {
        let a = self.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let b = other.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return b.starts(with: a)
    }
}
