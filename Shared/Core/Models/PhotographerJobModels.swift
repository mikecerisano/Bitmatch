import Foundation

enum PhotographerEventType: String, Codable, CaseIterable, Sendable {
    case wedding = "Wedding"
    case event = "Event"
    case portrait = "Portrait"
    case commercial = "Commercial"
}

enum FolderLayerKind: String, Codable, CaseIterable, Sendable {
    case dateAndJob
    case originals
    case photographer
    case camera
    case cardNumber
}

struct FolderLayer: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: FolderLayerKind
    var isEnabled: Bool
}

struct FolderRecipe: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var layers: [FolderLayer]

    static let wedding = FolderRecipe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Wedding",
        layers: FolderLayerKind.allCases.map {
            FolderLayer(id: UUID(), kind: $0, isEnabled: true)
        }
    )
}

struct FolderRecipeContext: Codable, Equatable, Sendable {
    let eventDate: Date
    let jobName: String
    let photographer: String
    let camera: String
    let cardNumber: Int
}

struct RenderedFolderRecipe: Codable, Equatable, Sendable {
    let components: [String]
    var relativePath: String { components.joined(separator: "/") }
}

enum FolderRecipeError: LocalizedError, Codable, Equatable, Sendable {
    case missingRequiredValue(String)
    case invalidCardNumber

    var errorDescription: String? {
        switch self {
        case .missingRequiredValue(let label): return "Enter a value for \(label)."
        case .invalidCardNumber: return "Card number must be greater than zero."
        }
    }
}

enum PhotographerLocalState: String, Codable, Sendable {
    case notStarted, copying, verifying, locallySafe, issues, cancelled
}

struct PhotographerIdentity: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
}

struct CardProvenance: Codable, Equatable, Sendable {
    var photographerID: UUID
    var photographerName: String
    var cameraName: String
    var cardNumber: Int
    var preliminaryFingerprint: String?
    var confirmedFingerprint: String?
}

struct CardIngest: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var provenance: CardProvenance
    var sourceDisplayName: String
    var renderedRelativePath: String
    var localState: PhotographerLocalState
    var startedAt: Date?
    var locallySafeAt: Date?
    var fileCount: Int
    var totalBytes: Int64
    var verifiedDestinationCount: Int

    init(
        id: UUID,
        provenance: CardProvenance,
        sourceDisplayName: String,
        renderedRelativePath: String,
        localState: PhotographerLocalState,
        startedAt: Date?,
        locallySafeAt: Date?,
        fileCount: Int,
        totalBytes: Int64,
        verifiedDestinationCount: Int = 0
    ) {
        self.id = id
        self.provenance = provenance
        self.sourceDisplayName = sourceDisplayName
        self.renderedRelativePath = renderedRelativePath
        self.localState = localState
        self.startedAt = startedAt
        self.locallySafeAt = locallySafeAt
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.verifiedDestinationCount = verifiedDestinationCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, provenance, sourceDisplayName, renderedRelativePath, localState
        case startedAt, locallySafeAt, fileCount, totalBytes, verifiedDestinationCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        provenance = try values.decode(CardProvenance.self, forKey: .provenance)
        sourceDisplayName = try values.decode(String.self, forKey: .sourceDisplayName)
        renderedRelativePath = try values.decode(String.self, forKey: .renderedRelativePath)
        localState = try values.decode(PhotographerLocalState.self, forKey: .localState)
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        locallySafeAt = try values.decodeIfPresent(Date.self, forKey: .locallySafeAt)
        fileCount = try values.decode(Int.self, forKey: .fileCount)
        totalBytes = try values.decode(Int64.self, forKey: .totalBytes)
        verifiedDestinationCount = try values.decodeIfPresent(Int.self, forKey: .verifiedDestinationCount) ?? 0
    }
}

struct PhotographerSetupSignature: Codable, Equatable, Sendable {
    let clientName: String
    let jobName: String
    let eventDate: Date
    let photographerName: String
    let cameraName: String
    let cardNumber: Int
    let recipe: FolderRecipe
}

struct PhotographerJob: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var eventDate: Date
    var clientName: String
    var jobName: String
    var eventType: PhotographerEventType
    var photographers: [PhotographerIdentity]
    var recipe: FolderRecipe
    var requiredLocalCopyCount: Int
    var cardIngests: [CardIngest]
    var createdAt: Date
    var updatedAt: Date
}

struct PhotographerPreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var eventType: PhotographerEventType
    var recipe: FolderRecipe
    var requiredLocalCopyCount: Int
}

struct PhotographerReportContext: Codable, Equatable, Sendable {
    let job: PhotographerJob
    let cardIngestID: UUID
    let analysis: CardAnalysis
    let verifiedDestinationCount: Int
    let warnings: [String]
}

enum PhotographerReportError: Error, Equatable {
    case cardNotFound
}

struct PhotographerReportPayload: Codable, Equatable, Sendable {
    struct CompanionCounts: Codable, Equatable, Sendable {
        let raw: Int
        let jpeg: Int
        let sidecar: Int
    }

    struct Result: Codable, Equatable, Sendable {
        let id: UUID
        let path: String
        let status: String
        let size: Int64
        let checksum: String?
        let destination: String?
        let destinationPath: String?
        let successful: Bool

        init(_ row: ResultRow) {
            id = row.id
            path = row.path
            status = row.status
            size = row.size
            checksum = row.checksum
            destination = row.destination
            destinationPath = row.destinationPath
            successful = row.isSuccessStatus
        }
    }

    let jobID: UUID
    let jobName: String
    let clientName: String
    let eventDate: Date
    let eventType: PhotographerEventType
    let card: CardIngest
    let analysis: CardAnalysis
    let companionCounts: CompanionCounts
    let requiredLocalCopyCount: Int
    let verifiedDestinationCount: Int
    let locallySafeAt: Date?
    let warnings: [String]
    let results: [Result]

    static func make(
        context: PhotographerReportContext,
        results: [ResultRow]
    ) throws -> PhotographerReportPayload {
        try make(context: context, results: results, finishedAt: nil)
    }

    static func make(
        context: PhotographerReportContext,
        results: [ResultRow],
        finishedAt: Date?
    ) throws -> PhotographerReportPayload {
        guard var card = context.job.cardIngests.first(where: { $0.id == context.cardIngestID }) else {
            throw PhotographerReportError.cardNotFound
        }

        var verifiedDestinationCount = context.verifiedDestinationCount
        if card.localState != .locallySafe {
            if let evidence = try finalEvidence(context: context, card: card, results: results) {
                card.localState = .locallySafe
                card.locallySafeAt = finishedAt ?? context.job.updatedAt
                card.provenance.confirmedFingerprint = evidence.fingerprint
                card.verifiedDestinationCount = evidence.destinationCount
                verifiedDestinationCount = evidence.destinationCount
            } else {
                card.localState = .issues
                card.locallySafeAt = nil
                card.provenance.confirmedFingerprint = nil
                card.verifiedDestinationCount = 0
                verifiedDestinationCount = 0
            }
        }

        let groups = context.analysis.companionGroups
        return PhotographerReportPayload(
            jobID: context.job.id,
            jobName: context.job.jobName,
            clientName: context.job.clientName,
            eventDate: context.job.eventDate,
            eventType: context.job.eventType,
            card: card,
            analysis: context.analysis,
            companionCounts: CompanionCounts(
                raw: groups.reduce(0) { $0 + $1.rawPaths.count },
                jpeg: groups.reduce(0) { $0 + $1.jpegPaths.count },
                sidecar: groups.reduce(0) { $0 + $1.sidecarPaths.count }
            ),
            requiredLocalCopyCount: context.job.requiredLocalCopyCount,
            verifiedDestinationCount: verifiedDestinationCount,
            locallySafeAt: card.locallySafeAt,
            warnings: context.warnings,
            results: results.map(Result.init)
        )
    }

    private static func finalEvidence(
        context: PhotographerReportContext,
        card: CardIngest,
        results: [ResultRow]
    ) throws -> (destinationCount: Int, fingerprint: String)? {
        let expectedPaths = context.analysis.sourcePaths
        let expectedSet = Set(expectedPaths)
        let identifiedRows = results.compactMap { row -> (String, ResultRow)? in
            guard let identity = destinationIdentity(for: row, packagePath: card.renderedRelativePath) else {
                return nil
            }
            return (identity, row)
        }
        let groups = Dictionary(grouping: identifiedRows, by: \.0).mapValues { $0.map(\.1) }
        let manifests = groups.mapValues { rows in
            rows.reduce(into: [String: String]()) { manifest, row in
                manifest[row.path] = row.checksum ?? ""
            }
        }
        let hasExactEvidence = !expectedPaths.isEmpty
            && expectedSet.count == expectedPaths.count
            && expectedPaths.count == card.fileCount
            && identifiedRows.count == results.count
            && groups.count >= context.job.requiredLocalCopyCount
            && groups.values.allSatisfy { rows in
                rows.count == expectedPaths.count
                    && Set(rows.map(\.path)) == expectedSet
                    && rows.allSatisfy(isVerified)
            }
        let checksumsAgree = expectedPaths.allSatisfy { path in
            let checksums = Set(manifests.values.compactMap { $0[path] })
            return checksums.count == 1 && checksums.first?.isEmpty == false
        }
        guard hasExactEvidence, checksumsAgree,
              let canonicalRows = groups.sorted(by: { $0.key < $1.key }).first?.value.sorted(by: { $0.path < $1.path }) else {
            return nil
        }
        return (groups.count, try PhotographerCardAnalyzer.confirmedFingerprint(results: canonicalRows))
    }

    private static func destinationIdentity(for row: ResultRow, packagePath: String) -> String? {
        if let destinationPath = nonblank(row.destinationPath) {
            let pathComponents = URL(fileURLWithPath: destinationPath).standardized.pathComponents
            let packageComponents = packagePath.split(separator: "/").map(String.init)
            if let packageStart = pathComponents.firstSubsequenceIndex(of: packageComponents) {
                let packageEnd = packageStart + packageComponents.count
                return NSString.path(withComponents: Array(pathComponents[..<packageEnd]))
            }
            return URL(fileURLWithPath: destinationPath).standardized.deletingLastPathComponent().path
        }
        return nonblank(row.destination)
    }

    private static func isVerified(_ row: ResultRow) -> Bool {
        row.isSuccessStatus
            && nonblank(row.path) != nil
            && nonblank(row.checksum) != nil
            && nonblank(row.destinationPath) != nil
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private extension Array where Element: Equatable {
    func firstSubsequenceIndex(of subsequence: [Element]) -> Int? {
        guard !subsequence.isEmpty, subsequence.count <= count else { return nil }
        for start in 0...(count - subsequence.count) {
            if Array(self[start..<(start + subsequence.count)]) == subsequence {
                return start
            }
        }
        return nil
    }
}
