import Foundation

enum FileTreeEnumerator {
    static func enumerateRegularFiles(base: URL) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            while let item = enumerator.nextObject() as? URL {
                if let isFile = try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true {
                    files.append(item)
                }
            }
        }
        return files
    }

    static func countRegularFiles(base: URL) -> Int {
        var count = 0
        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let item = enumerator.nextObject() as? URL {
                if Task.isCancelled { return count }
                if let isFile = try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true {
                    count += 1
                }
            }
        }
        return count
    }
}
