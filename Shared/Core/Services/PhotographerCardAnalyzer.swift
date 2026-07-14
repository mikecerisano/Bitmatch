import CryptoKit
import Foundation

struct PhotoCompanionGroup: Codable, Equatable, Sendable {
    let stem: String
    let rawPaths: [String]
    let jpegPaths: [String]
    let sidecarPaths: [String]
}

struct CardAnalysis: Codable, Equatable, Sendable {
    let fingerprint: String
    let fileCount: Int
    let totalBytes: Int64
    let companionGroups: [PhotoCompanionGroup]
}

enum CardAnalysisError: Error, Equatable {
    case incompleteVerification
}

enum PhotographerCardAnalyzer {
    private static let rawExtensions: Set<String> = [
        "arw", "cr2", "cr3", "nef", "nrw", "raf", "orf", "rw2", "dng"
    ]
    private static let jpegExtensions: Set<String> = ["jpg", "jpeg"]
    private static let sidecarExtensions: Set<String> = ["xmp", "aae", "dop", "cos"]

    static func preliminaryAnalysis(entries: [FileEntry]) throws -> CardAnalysis {
        let canonicalEntries = entries.sorted {
            $0.relativePath.lowercased() < $1.relativePath.lowercased()
        }
        var groups: [String: GroupPaths] = [:]
        var fingerprintLines: [String] = []

        for entry in canonicalEntries {
            let canonicalPath = entry.relativePath.lowercased()
            let modificationTime = Int64(entry.modificationDate?.timeIntervalSince1970 ?? 0)
            fingerprintLines.append("\(canonicalPath)\0\(entry.size)\0\(modificationTime)\n")

            let path = canonicalPath as NSString
            let fileExtension = path.pathExtension
            guard rawExtensions.contains(fileExtension)
                    || jpegExtensions.contains(fileExtension)
                    || sidecarExtensions.contains(fileExtension) else {
                continue
            }

            let stem = path.deletingPathExtension
            var group = groups[stem, default: GroupPaths()]
            if rawExtensions.contains(fileExtension) {
                group.rawPaths.append(entry.relativePath)
            } else if jpegExtensions.contains(fileExtension) {
                group.jpegPaths.append(entry.relativePath)
            } else {
                group.sidecarPaths.append(entry.relativePath)
            }
            groups[stem] = group
        }

        var hasher = SHA256()
        for line in fingerprintLines.sorted() {
            hasher.update(data: Data(line.utf8))
        }

        let companionGroups = groups.keys.sorted().map { stem in
            let paths = groups[stem]!
            return PhotoCompanionGroup(
                stem: stem,
                rawPaths: paths.rawPaths.sorted(),
                jpegPaths: paths.jpegPaths.sorted(),
                sidecarPaths: paths.sidecarPaths.sorted()
            )
        }

        return CardAnalysis(
            fingerprint: digestString(hasher.finalize()),
            fileCount: entries.count,
            totalBytes: entries.reduce(0) { $0 + $1.size },
            companionGroups: companionGroups
        )
    }

    static func confirmedFingerprint(results: [ResultRow]) throws -> String {
        var hasher = SHA256()
        for result in results.sorted(by: { $0.path < $1.path }) {
            guard result.isSuccessStatus, let checksum = result.checksum else {
                throw CardAnalysisError.incompleteVerification
            }
            hasher.update(data: Data("\(result.path)\0\(result.size)\0\(checksum)".utf8))
        }
        return digestString(hasher.finalize())
    }

    private static func digestString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct GroupPaths {
        var rawPaths: [String] = []
        var jpegPaths: [String] = []
        var sidecarPaths: [String] = []
    }
}
