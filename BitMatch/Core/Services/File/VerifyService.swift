import Foundation

enum VerifyService {
    static func compare(
        leftURL: URL,
        rightURL: URL,
        relativePath: String,
        verificationMode: VerificationMode
    ) async -> ResultRow {
        do {
            let leftSize = try FileManager.default.attributesOfItem(atPath: leftURL.path)[.size] as? Int64 ?? 0
            let rightSize = try FileManager.default.attributesOfItem(atPath: rightURL.path)[.size] as? Int64 ?? 0

            guard leftSize == rightSize else {
                return ResultRow(path: relativePath, status: "Size Mismatch", size: leftSize, checksum: nil, destination: nil)
            }

            if verificationMode.useChecksum {
                do {
                    let checksumService = SharedChecksumService.shared
                    let checksumAlgorithm = verificationMode.checksumTypes.first ?? .sha256

                    let leftChecksum = try await checksumService.generateChecksum(for: leftURL, type: checksumAlgorithm, progressCallback: nil)
                    let rightChecksum = try await checksumService.generateChecksum(for: rightURL, type: checksumAlgorithm, progressCallback: nil)

                    let checksumMatch = leftChecksum == rightChecksum
                    let status = checksumMatch ? "✅ Verified Match" : "❌ Checksum Mismatch"
                    return ResultRow(path: relativePath, status: status, size: leftSize, checksum: leftChecksum, destination: nil)
                } catch {
                    return ResultRow(path: relativePath, status: "❌ Checksum Error: \(error.localizedDescription)", size: leftSize, checksum: nil, destination: nil)
                }
            } else {
                return ResultRow(path: relativePath, status: "✅ Match", size: leftSize, checksum: nil, destination: nil)
            }
        } catch {
            return ResultRow(path: relativePath, status: "Error: \(error.localizedDescription)", size: 0, checksum: nil, destination: nil)
        }
    }
}
