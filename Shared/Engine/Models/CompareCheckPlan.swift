// CompareCheckPlan.swift - What each verification mode checks in Compare.
import Foundation

/// The checks Compare runs on each file present in both folders. This is the
/// single source for both `ComparisonCoordinator` and the words on screen, so
/// the summary can never promise a check the engine skipped.
///
/// It is deliberately independent of `VerificationMode.checksumTypes`, which
/// belongs to the copy engine: Paranoid Compare is byte-by-byte plus SHA-256
/// whatever that property lists (THESIS decisions, 2026-09-25).
struct CompareCheckPlan: Equatable, Sendable {
    /// Compare every byte of the two files.
    let byteByByte: Bool
    /// Checksums compared, in order. Empty means sizes only.
    let checksums: [ChecksumAlgorithm]

    /// True when the file contents are actually read and compared.
    var verifiesContents: Bool { byteByByte || !checksums.isEmpty }

    static func make(for mode: VerificationMode) -> Self {
        switch mode {
        case .quick: Self(byteByByte: false, checksums: [])
        case .standard: Self(byteByByte: false, checksums: [.sha256])
        case .thorough: Self(byteByByte: false, checksums: [.sha256, .md5])
        case .paranoid: Self(byteByByte: true, checksums: [.sha256])
        }
    }

    /// One line for the screen, e.g. "Byte-by-byte and SHA-256".
    var summary: String {
        let names = checksums.map(\.rawValue)
        if byteByByte {
            return (["Byte-by-byte"] + names).joined(separator: " and ")
        }
        if names.isEmpty {
            return "File sizes only, contents not verified"
        }
        return names.joined(separator: " and ") + " checksums"
    }
}
