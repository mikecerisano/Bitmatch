import Foundation

enum PreScanService {
    /// Streaming variant: counts files already present at destination without holding a full source list
    static func countAlreadyPresentStreaming(
        sourceBase: URL,
        destRoot: URL,
        verificationMode: VerificationMode
    ) async -> Int {
        let fm = FileManager.default
        var count = 0
        if let enumerator = fm.enumerator(
            at: sourceBase,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                autoreleasepool {
                    guard let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true else { return }
                    let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
                    let relative = String(fileURL.path.dropFirst(sourceBase.path.count + 1))
                    let destURL = destRoot.appendingPathComponent(relative)
                    if fm.fileExists(atPath: destURL.path) {
                        let destSize = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.int64Value ?? -1
                        if destSize == Int64(values?.fileSize ?? -2) {
                            // Keep prescan light: size-only match for seeding progress
                            count += 1
                        }
                    }
                }
            }
        }
        return count
    }
    static func countAlreadyPresent(
        sourceFiles: [URL],
        sourceBase: URL,
        destRoot: URL,
        verificationMode: VerificationMode
    ) async -> Int {
        let fm = FileManager.default
        var count = 0
        for fileURL in sourceFiles {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let relative = String(fileURL.path.dropFirst(sourceBase.path.count + 1))
                let destURL = destRoot.appendingPathComponent(relative)
                if fm.fileExists(atPath: destURL.path) {
                    let destSize = (try fm.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.int64Value ?? -1
                    if destSize == Int64(values.fileSize ?? -2) {
                        if verificationMode.useChecksum, let fsize = values.fileSize, fsize > 0, fsize <= 5 * 1024 * 1024 {
                            do {
                                let srcHash = try await SharedChecksumService.shared.generateChecksum(for: fileURL, type: .sha256, progressCallback: nil)
                                let dstHash = try await SharedChecksumService.shared.generateChecksum(for: destURL, type: .sha256, progressCallback: nil)
                                if srcHash == dstHash { count += 1 }
                            } catch {
                                // ignore
                            }
                        } else {
                            count += 1
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return count
    }
}
