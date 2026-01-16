import Foundation

enum FileTreeEnumerator {
    // Note: enumerateRegularFiles was removed - it loaded all files into memory
    // and was never used. Use streaming enumeration via FileCopyService._EnumeratorSource
    // or the countRegularFiles function below for counting only.

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
