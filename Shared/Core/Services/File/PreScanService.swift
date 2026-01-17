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
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        if let enumerator = fm.enumerator(
            at: sourceBase,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                let relative = String(fileURL.path.dropFirst(sourceBase.path.count + 1))
                let destURL = destRoot.appendingPathComponent(relative)
                if fm.fileExists(atPath: destURL.path) {
                    let destAttributes = try? fm.attributesOfItem(atPath: destURL.path)
                    let destSize = (destAttributes?[.size] as? NSNumber)?.int64Value ?? -1
                    let sourceSize = Int64(values.fileSize ?? -2)
                    if destSize == sourceSize {
                        if verificationMode == .quick {
                            if modificationDatesMatch(
                                source: values.contentModificationDate,
                                destination: destAttributes?[.modificationDate] as? Date
                            ) {
                                count += 1
                            }
                        } else {
                            do {
                                if try await checksumsMatch(
                                    source: fileURL,
                                    destination: destURL,
                                    verificationMode: verificationMode
                                ) {
                                    count += 1
                                }
                            } catch is CancellationError {
                                return count
                            } catch {
                                // ignore
                            }
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
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let relative = String(fileURL.path.dropFirst(sourceBase.path.count + 1))
                let destURL = destRoot.appendingPathComponent(relative)
                if fm.fileExists(atPath: destURL.path) {
                    let destAttributes = try fm.attributesOfItem(atPath: destURL.path)
                    let destSize = (destAttributes[.size] as? NSNumber)?.int64Value ?? -1
                    if destSize == Int64(values.fileSize ?? -2) {
                        if verificationMode == .quick {
                            if modificationDatesMatch(
                                source: values.contentModificationDate,
                                destination: destAttributes[.modificationDate] as? Date
                            ) {
                                count += 1
                            }
                        } else {
                            do {
                                if try await checksumsMatch(
                                    source: fileURL,
                                    destination: destURL,
                                    verificationMode: verificationMode
                                ) {
                                    count += 1
                                }
                            } catch is CancellationError {
                                return count
                            } catch {
                                // ignore
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return count
    }

    private static let modificationTolerance: TimeInterval = 2.0

    private static func modificationDatesMatch(source: Date?, destination: Date?) -> Bool {
        guard let source, let destination else { return false }
        return abs(source.timeIntervalSince(destination)) <= modificationTolerance
    }

    private static func checksumsMatch(
        source: URL,
        destination: URL,
        verificationMode: VerificationMode
    ) async throws -> Bool {
        let types = verificationMode.checksumTypes
        guard !types.isEmpty else { return false }
        for type in types {
            let srcHash = try await SharedChecksumService.shared.generateChecksum(
                for: source,
                type: type,
                progressCallback: nil
            )
            let dstHash = try await SharedChecksumService.shared.generateChecksum(
                for: destination,
                type: type,
                progressCallback: nil
            )
            if srcHash.lowercased() != dstHash.lowercased() {
                return false
            }
        }
        return true
    }
}
