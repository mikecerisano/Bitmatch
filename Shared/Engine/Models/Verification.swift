// Verification.swift - What BitMatch checks, and the errors and results it reports.
import Foundation

// MARK: - Checksum Algorithm
enum ChecksumAlgorithm: String, CaseIterable, Identifiable, Codable {
    case sha256 = "SHA-256"
    case sha1 = "SHA-1"
    case md5 = "MD5"

    var id: String { self.rawValue }

    var description: String {
        switch self {
        case .sha256: return "SHA-256 (Recommended)"
        case .sha1: return "SHA-1"
        case .md5: return "MD5 (Legacy)"
        }
    }

    /// Security 9: MD5 and SHA-1 are cryptographically broken; kept only for MHL compatibility
    var isDeprecated: Bool {
        switch self {
        case .sha256: return false
        case .sha1, .md5: return true
        }
    }
}

// MARK: - BitMatch Error Types
enum BitMatchError: LocalizedError {
    case fileAccessDenied(URL)
    case fileNotFound(URL)
    case checksumMismatch(String, String)
    case operationCancelled
    case insufficientStorage(Int64, Int64) // required, available
    case networkError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileAccessDenied(let url):
            return "Access denied to file: \(url.lastPathComponent)"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch - Expected: \(expected), Got: \(actual)"
        case .operationCancelled:
            return "Operation was cancelled"
        case .insufficientStorage(let required, let available):
            return "Insufficient storage - Need: \(ByteCountFormatter().string(fromByteCount: required)), Available: \(ByteCountFormatter().string(fromByteCount: available))"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Verification Result
struct VerificationResult: Codable {
    let sourceChecksum: String
    let destinationChecksum: String
    let matches: Bool
    let checksumType: ChecksumAlgorithm
    let processingTime: TimeInterval
    let fileSize: Int64
    
    var isValid: Bool { matches }
    
    var description: String {
        if matches {
            return "✅ Files match - \(checksumType.rawValue) verified"
        } else {
            return "❌ Files differ - \(checksumType.rawValue) mismatch"
        }
    }
}

// MARK: - Verification Mode
enum VerificationMode: String, CaseIterable, Identifiable, Codable {
    case quick = "Quick"
    case standard = "Standard"
    case thorough = "Thorough" 
    case paranoid = "Paranoid"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .quick: return "Quick checks file sizes only; file contents are not checksum-verified."
        case .standard: return "Standard compares SHA-256 checksums to verify each copy matches its source."
        case .thorough: return "Thorough verifies each copy with SHA-256 and MD5 checksums."
        case .paranoid: return "Paranoid adds a byte-by-byte comparison to checksum verification."
        }
    }
    
    var requiresMHL: Bool {
        switch self {
        case .quick, .standard: return false
        case .thorough, .paranoid: return true
        }
    }
    
    var useChecksum: Bool {
        switch self {
        case .quick: return false
        case .standard, .thorough, .paranoid: return true
        }
    }
    
    /// Checksums computed for this mode. Paranoid adds a byte-by-byte
    /// comparison on top of SHA-256; it does not add MD5 or SHA-1.
    var checksumTypes: [ChecksumAlgorithm] {
        switch self {
        case .quick: return []
        case .standard: return [.sha256]
        case .thorough: return [.sha256, .md5]
        case .paranoid: return [.sha256]
        }
    }
}
