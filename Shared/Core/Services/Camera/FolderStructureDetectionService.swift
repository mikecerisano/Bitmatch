// Core/Services/Camera/FolderStructureDetectionService.swift
import Foundation
import BitMatchEngine

/// Service for detecting cameras based on folder structure patterns.
///
/// The brand comes from `CardLayoutClassifier`, the same rules the Mac
/// auto-detect uses. This stage only adds the two brandless answers:
/// "Professional" for a pro card root it cannot place, and "Generic" for
/// a DCIM card. It no longer treats DCIM + MISC as Canon or MISC as GoPro
/// (audit finding D), and it matches whole path components, so a folder
/// named CARRIE is not ARRI.
final class FolderStructureDetectionService: Sendable {
    static let shared = FolderStructureDetectionService()
    private init() {}

    // MARK: - Public Interface

    func detectCameraFromStructure(at url: URL) -> String? {
        let listing = CardListing.scan(url)
        guard !Task.isCancelled else { return nil }

        if let match = CardLayoutClassifier.classify(listing), let brand = match.brand {
            SharedLogger.info("Folder structure match: \(brand) via \(match.evidence)", category: .transfer)
            return brand
        }

        let topLevel = Set(listing.subdirectories(of: ""))
        if !topLevel.isDisjoint(with: ["CLIPS", "CONTENTS", "PROAV"]) {
            return "Professional"
        }
        if topLevel.contains("DCIM") {
            return "Generic"
        }
        return nil
    }
}
