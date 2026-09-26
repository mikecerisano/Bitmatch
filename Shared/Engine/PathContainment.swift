// PathContainment.swift - The one rule for "is this path inside that folder".
import Foundation

/// Every containment and same-folder check in the engine uses this rule:
/// compare path components (never raw prefixes, so "/Volumes/T7" does not
/// contain "/Volumes/T70"), with "/private/var", "/private/etc" and
/// "/private/tmp" treated as the "/var", "/etc" and "/tmp" macOS aliases
/// them to. Callers resolve symlinks first when they need to; this works
/// on text and never touches the disk.
enum PathContainment {
    /// Standardizing drops "/private" from a path only when the rest exists
    /// ("/private/var/mobile" becomes "/var/mobile", but a longer path that
    /// does not exist keeps it), so the same place could fail to match
    /// itself. Both sides drop it the way macOS aliases these folders.
    static func comparableComponents(_ path: String) -> [String] {
        var components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        if components.count > 2, components[1] == "private", ["var", "etc", "tmp"].contains(components[2]) {
            components.remove(at: 1)
        }
        return components
    }

    /// The path as the rule compares it.
    static func comparablePath(_ path: String) -> String {
        let components = comparableComponents(path)
        guard components.first == "/" else { return components.joined(separator: "/") }
        return "/" + components.dropFirst().joined(separator: "/")
    }

    static func isSamePath(_ first: String, _ second: String) -> Bool {
        comparableComponents(first) == comparableComponents(second)
    }

    /// `candidate` is `root` or inside it.
    static func isWithin(_ candidate: String, root: String) -> Bool {
        let candidateComponents = comparableComponents(candidate)
        let rootComponents = comparableComponents(root)
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy(==)
    }

    /// `candidate` is inside `root` and is not `root` itself.
    static func isStrictlyWithin(_ candidate: String, root: String) -> Bool {
        comparableComponents(candidate).count > comparableComponents(root).count
            && isWithin(candidate, root: root)
    }
}
