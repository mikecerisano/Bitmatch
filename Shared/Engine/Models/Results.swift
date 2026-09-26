// Results.swift - One row per file per backup, and how it ended.
import Foundation

/// How one file on one backup ended. The engine writes `statusText` into
/// `ResultRow.status`, and `ResultRow.isSuccessStatus` reads it back through
/// `init(statusText:)`, so the text and the rule that judges it cannot drift.
enum ResultOutcome: CaseIterable, Equatable, Sendable {
    /// Copied and confirmed by checksum or byte comparison.
    case verified
    /// Copied without verification (Quick mode). A success, never "verified".
    case copiedUnverified
    case checksumMismatch
    case failed

    var statusText: String {
        switch self {
        case .verified: "✅ Verified"
        case .copiedUnverified: "✅ Copied"
        case .checksumMismatch: "⚠️ Checksum Mismatch"
        case .failed: "❌ Failed"
        }
    }

    var isSuccess: Bool { self == .verified || self == .copiedUnverified }
    var isVerified: Bool { self == .verified }

    init?(statusText: String) {
        guard let match = Self.allCases.first(where: { $0.statusText == statusText }) else { return nil }
        self = match
    }
}

// MARK: - Result Row
struct ResultRow: Identifiable {
    let id: UUID
    let path: String
    let status: String
    let size: Int64
    let checksum: String?
    let destination: String?
    let destinationPath: String?
    
    init(id: UUID = UUID(),
         path: String,
         status: String,
         size: Int64,
         checksum: String?,
         destination: String?,
         destinationPath: String? = nil) {
        self.id = id
        self.path = path
        self.status = status
        self.size = size
        self.checksum = checksum
        self.destination = destination
        self.destinationPath = destinationPath
    }
    
    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var isSuccessStatus: Bool {
        Self.isSuccessStatus(status)
    }

    /// Single source of truth for whether a result row represents a verified
    /// success. Fail-safe: a status must positively signal success ("✅") and
    /// carry no failure marker; anything unrecognized counts as an issue.
    /// Substring checks like `lowercased().contains("match")` are forbidden
    /// here — "Checksum Mismatch" contains "match".
    static func isSuccessStatus(_ status: String) -> Bool {
        if let outcome = ResultOutcome(statusText: status) {
            return outcome.isSuccess
        }
        // Older wording (saved history, compare descriptions): fail-safe rule.
        guard status.contains("✅") else { return false }
        let lowercased = status.lowercased()
        let failureMarkers = ["❌", "⚠️", "mismatch", "fail", "error", "missing"]
        return !failureMarkers.contains { lowercased.contains($0) }
    }

    var isVerifiedStatus: Bool {
        Self.isVerifiedStatus(status)
    }

    /// Whether a row counts as verified, not just copied (Promise 2): only
    /// `.verified`, or older text that is a success and says "verified" or
    /// "match" without "unverified" / "not verified".
    static func isVerifiedStatus(_ status: String) -> Bool {
        guard isSuccessStatus(status) else { return false }
        if let outcome = ResultOutcome(statusText: status) {
            return outcome.isVerified
        }
        let lowercased = status.lowercased()
        let saysVerified = lowercased.contains("verified") || lowercased.contains("match")
        let deniesVerified = lowercased.contains("unverified") || lowercased.contains("not verified")
        return saysVerified && !deniesVerified
    }
}

// MARK: - Report Preferences  
struct ReportPrefs: Codable {
    /// Actual copy mode; nil preserves legacy folder-comparison preferences.
    var verificationMode: VerificationMode? = nil
    var includeThumbnails: Bool = false
    var clientName: String = ""
    var projectName: String = ""
    var production: String = ""
    var company: String = ""
    var notes: String = ""
    var makeReport: Bool = true
    var verifyWithChecksum: Bool = true
    var enableAutoCameraDetection: Bool = true
    var autoPopulateSource: Bool = false
    var showCameraDetectionNotifications: Bool = true
    var checksumAlgorithm: ChecksumAlgorithm = .sha256
}

extension ResultRow: Codable {
    enum CodingKeys: String, CodingKey {
        case id, path, status, size, checksum, destination, destinationPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let path = try container.decode(String.self, forKey: .path)
        let status = try container.decode(String.self, forKey: .status)
        let size = try container.decode(Int64.self, forKey: .size)
        let checksum = try container.decodeIfPresent(String.self, forKey: .checksum)
        let destination = try container.decodeIfPresent(String.self, forKey: .destination)
        let destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath)

        self.init(id: id, path: path, status: status, size: size, checksum: checksum, destination: destination, destinationPath: destinationPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(status, forKey: .status)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(checksum, forKey: .checksum)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encodeIfPresent(destinationPath, forKey: .destinationPath)
    }
}
