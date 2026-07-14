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
