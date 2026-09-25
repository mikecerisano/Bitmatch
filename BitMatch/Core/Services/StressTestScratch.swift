// Core/Services/StressTestScratch.swift
//
// The folders the debug stress test (`DevModeManager.runStressTest`) copies
// from and to. They live in the temp folder under one name prefix, so the
// rest of the app can recognise them in every build: the Mac never
// remembers one as a last-used backup or a recent folder, even in a build
// where the stress test itself is compiled out.
import Foundation

enum StressTestScratch {
    static let namePrefix = "bitmatch_stress_"

    /// A new, not yet created folder for one run: `kind` is "src" or "dst".
    static func newFolder(kind: String, in temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL {
        temporaryDirectory.appendingPathComponent("\(namePrefix)\(kind)_\(UUID().uuidString)", isDirectory: true)
    }

    /// True for a stress-test folder, or anything inside one, in the temp
    /// folder. A folder elsewhere that happens to share the prefix is not
    /// one.
    static func isScratch(_ url: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> Bool {
        let roots = pathVariants(temporaryDirectory)
        return pathVariants(url).contains { path in
            roots.contains { root in
                path.count > root.count
                    && Array(path.prefix(root.count)) == root
                    && path[root.count].hasPrefix(namePrefix)
            }
        }
    }

    /// Stress-test folders left in the temp folder, for example by a run the
    /// app quit during.
    static func leftovers(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)) ?? []
        return names
            .filter { $0.hasPrefix(namePrefix) }
            .map { temporaryDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    /// Deletes `folders`, refusing anything that is not a stress-test folder
    /// so a wrong URL can never remove a real one. Returns what it could not
    /// delete.
    @discardableResult
    static func remove(_ folders: [URL], temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> [URL] {
        folders.filter { folder in
            guard isScratch(folder, temporaryDirectory: temporaryDirectory),
                  FileManager.default.fileExists(atPath: folder.path) else { return false }
            do {
                try FileManager.default.removeItem(at: folder)
                return false
            } catch {
                return true
            }
        }
    }

    /// /var and /private/var are the same folder on macOS, and a folder
    /// that no longer exists does not resolve the way its parent does, so
    /// every spelling is compared.
    private static func pathVariants(_ url: URL) -> [[String]] {
        let spellings = [url.standardizedFileURL.pathComponents,
                         url.standardizedFileURL.resolvingSymlinksInPath().pathComponents]
        return spellings.flatMap { components -> [[String]] in
            if components.count > 2, components[1] == "private" {
                return [components, [components[0]] + components.dropFirst(2)]
            }
            if components.count > 1, components[1] == "var" || components[1] == "tmp" {
                return [components, [components[0], "private"] + components.dropFirst(1)]
            }
            return [components]
        }
    }
}
