// ReportCoordinator.swift - Extracted from SharedAppCoordinator for report generation
import Foundation

/// Handles report generation operations
@MainActor
final class ReportCoordinator {
    private let platformManager: PlatformManager

    init(platformManager: PlatformManager) {
        self.platformManager = platformManager
    }

    /// Generate a report from a completed operation
    func generateReport(
        sourceURL: URL?,
        sourceFolderInfo: EnhancedFolderInfo?,
        destinationURLs: [URL],
        destinationFolderInfos: [URL: EnhancedFolderInfo],
        detectedCamera: CameraCard?,
        timingService: OperationTimingService,
        verificationMode: VerificationMode,
        cameraLabelSettings: CameraLabelSettings,
        operationState: OperationState
    ) async throws {
        // Build a minimal TransferCard from current state
        let srcInfo: FolderInfo = try {
            if let info = sourceFolderInfo {
                return FolderInfo(url: info.url, fileCount: info.fileCount, totalSize: info.totalSize, lastModified: info.lastModified, isInternalDrive: false)
            } else if let src = sourceURL {
                return FolderInfo(url: src, fileCount: 0, totalSize: 0, lastModified: Date(), isInternalDrive: false)
            } else {
                throw NSError(domain: "BitMatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing source info for report"])
            }
        }()

        let destInfos: [FolderInfo] = destinationURLs.map { url in
            if let info = destinationFolderInfos[url] {
                return FolderInfo(url: info.url, fileCount: info.fileCount, totalSize: info.totalSize, lastModified: info.lastModified, isInternalDrive: false)
            } else {
                return FolderInfo(url: url, fileCount: 0, totalSize: 0, lastModified: Date(), isInternalDrive: false)
            }
        }

        let transfer = TransferCard(
            source: srcInfo,
            destinations: destInfos,
            cameraCard: detectedCamera,
            metadata: TransferMetadata(
                sourceURL: srcInfo.url,
                destinationURLs: destInfos.map { $0.url },
                startTime: timingService.currentTiming?.startTime ?? Date(),
                endTime: Date(),
                totalFiles: sourceFolderInfo?.fileCount ?? 0,
                totalSize: sourceFolderInfo?.totalSize ?? 0,
                verificationMode: verificationMode,
                cameraSettings: cameraLabelSettings
            ),
            progress: 1.0,
            state: operationState
        )

        let config = SharedReportGenerationService.ReportConfiguration.default()
        let generator = SharedReportGenerationService()
        let result = try await generator.generateMasterReport(transfers: [transfer], configuration: config)

        // Persist to temp and open
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let pdfURL = tempDir.appendingPathComponent("BitMatch_Report_\(timestamp).pdf").nonConflictingSibling()
        let jsonURL = pdfURL.deletingPathExtension().appendingPathExtension("json").nonConflictingSibling()
        try result.pdfData.write(to: pdfURL)
        try result.jsonData.write(to: jsonURL)

        _ = await platformManager.openURL(pdfURL)
    }
}
