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
    let sourcePaths: [String]

    init(
        fingerprint: String,
        fileCount: Int,
        totalBytes: Int64,
        companionGroups: [PhotoCompanionGroup],
        sourcePaths: [String] = []
    ) {
        self.fingerprint = fingerprint
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.companionGroups = companionGroups
        self.sourcePaths = sourcePaths
    }

    private enum CodingKeys: String, CodingKey {
        case fingerprint, fileCount, totalBytes, companionGroups, sourcePaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        fileCount = try container.decode(Int.self, forKey: .fileCount)
        totalBytes = try container.decode(Int64.self, forKey: .totalBytes)
        companionGroups = try container.decode([PhotoCompanionGroup].self, forKey: .companionGroups)
        sourcePaths = try container.decodeIfPresent([String].self, forKey: .sourcePaths) ?? []
    }
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
        try Task.checkCancellation()
        let canonicalEntries = try cancellationCheckedSorted(entries) {
            $0.relativePath.lowercased() < $1.relativePath.lowercased()
        }
        var groups: [String: GroupPaths] = [:]
        var fingerprintLines: [String] = []

        for entry in canonicalEntries {
            try Task.checkCancellation()
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
        for line in try cancellationCheckedSorted(fingerprintLines, by: <) {
            try Task.checkCancellation()
            hasher.update(data: Data(line.utf8))
        }

        var companionGroups: [PhotoCompanionGroup] = []
        for stem in try cancellationCheckedSorted(Array(groups.keys), by: <) {
            try Task.checkCancellation()
            let paths = groups[stem]!
            companionGroups.append(PhotoCompanionGroup(
                stem: stem,
                rawPaths: try cancellationCheckedSorted(paths.rawPaths, by: <),
                jpegPaths: try cancellationCheckedSorted(paths.jpegPaths, by: <),
                sidecarPaths: try cancellationCheckedSorted(paths.sidecarPaths, by: <)
            ))
        }

        var totalBytes: Int64 = 0
        var sourcePaths: [String] = []
        sourcePaths.reserveCapacity(entries.count)
        for entry in entries {
            try Task.checkCancellation()
            totalBytes += entry.size
            sourcePaths.append(entry.url.path)
        }
        sourcePaths = try cancellationCheckedSorted(sourcePaths, by: <)

        return CardAnalysis(
            fingerprint: digestString(hasher.finalize()),
            fileCount: entries.count,
            totalBytes: totalBytes,
            companionGroups: companionGroups,
            sourcePaths: sourcePaths
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

    private static func cancellationCheckedSorted<Element>(
        _ values: [Element],
        by areInIncreasingOrder: (Element, Element) -> Bool
    ) throws -> [Element] {
        try Task.checkCancellation()
        guard values.count > 1 else { return values }
        var source = values
        var width = 1
        while width < source.count {
            try Task.checkCancellation()
            var merged = source
            var start = 0
            while start < source.count {
                try Task.checkCancellation()
                let middle = min(start + width, source.count)
                let end = min(start + width * 2, source.count)
                var left = start
                var right = middle
                var destination = start
                while left < middle || right < end {
                    try Task.checkCancellation()
                    if right >= end || (left < middle && !areInIncreasingOrder(source[right], source[left])) {
                        merged[destination] = source[left]
                        left += 1
                    } else {
                        merged[destination] = source[right]
                        right += 1
                    }
                    destination += 1
                }
                start = end
            }
            source = merged
            width *= 2
        }
        return source
    }

    private struct GroupPaths {
        var rawPaths: [String] = []
        var jpegPaths: [String] = []
        var sidecarPaths: [String] = []
    }
}
