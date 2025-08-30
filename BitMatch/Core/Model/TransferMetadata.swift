// Core/Models/TransferMetadata.swift
import Foundation

// MARK: - Transfer Metadata Structures for JSON Reports

/// Main metadata structure for transfer operations
struct TransferMetadata: Codable {
    let version: String
    let jobId: UUID
    let timestamp: Date
    let production: ProductionInfo
    let source: SourceInfo
    let destination: DestinationInfo
    let verification: VerificationInfo
    let performance: PerformanceInfo
}

/// Production/project information
struct ProductionInfo: Codable {
    let title: String
    let company: String
    let client: String
}

/// Source folder information
struct SourceInfo: Codable {
    let path: String
    let originalName: String
    let bytes: Int64
    let files: Int
    let cameraDetected: String
}

/// Destination folder information with labeling details
struct DestinationInfo: Codable {
    let path: String
    let cameraLabel: String
    let labelPosition: String
    let separator: String
    let autoNumbered: Bool
}

/// Verification process information
struct VerificationInfo: Codable {
    let method: String
    let mode: String
    let results: VerificationResults
}

/// Verification results summary
struct VerificationResults: Codable {
    let matched: Int
    let mismatched: Int
    let missing: Int
    let extra: Int
}

/// Performance metrics for the operation
struct PerformanceInfo: Codable {
    let duration: TimeInterval
    let throughput: String
    let workers: Int
}

// MARK: - Convenience Extensions
extension TransferMetadata {
    /// Create metadata for a copy and verify operation
    static func forCopyOperation(
        jobId: UUID,
        jobStart: Date,
        sourceURL: URL?,
        destinationPath: String,
        sourceFolderInfo: FolderInfo?,
        cameraLabel: CameraLabelSettings,
        detectedCamera: CameraType,
        prefs: ReportPrefs,
        verificationMode: VerificationMode,
        matchCount: Int,
        workers: Int,
        totalBytesProcessed: Int64
    ) -> TransferMetadata {
        let duration = Date().timeIntervalSince(jobStart)
        let throughputMBps = duration > 0 ? Double(totalBytesProcessed) / duration / 1_048_576 : 0
        
        return TransferMetadata(
            version: "1.0",
            jobId: jobId,
            timestamp: Date(),
            production: ProductionInfo(
                title: prefs.production,
                company: prefs.company,
                client: prefs.client
            ),
            source: SourceInfo(
                path: sourceURL?.path ?? "",
                originalName: sourceURL?.lastPathComponent ?? "",
                bytes: sourceFolderInfo?.totalSize ?? 0,
                files: sourceFolderInfo?.fileCount ?? 0,
                cameraDetected: detectedCamera.rawValue
            ),
            destination: DestinationInfo(
                path: destinationPath,
                cameraLabel: cameraLabel.label,
                labelPosition: cameraLabel.position.rawValue,
                separator: cameraLabel.separator.rawValue,
                autoNumbered: cameraLabel.autoNumber
            ),
            verification: VerificationInfo(
                method: verificationMode.rawValue,
                mode: "copy-and-verify",
                results: VerificationResults(
                    matched: matchCount,
                    mismatched: 0,
                    missing: 0,
                    extra: 0
                )
            ),
            performance: PerformanceInfo(
                duration: duration,
                throughput: String(format: "%.1f MB/s", throughputMBps),
                workers: workers
            )
        )
    }
    
    /// Create metadata for a comparison operation
    static func forCompareOperation(
        jobId: UUID,
        jobStart: Date,
        leftURL: URL,
        rightURL: URL,
        leftFolderInfo: FolderInfo?,
        prefs: ReportPrefs,
        verificationMode: VerificationMode,
        matchCount: Int,
        workers: Int
    ) -> TransferMetadata {
        let duration = Date().timeIntervalSince(jobStart)
        
        return TransferMetadata(
            version: "1.0",
            jobId: jobId,
            timestamp: Date(),
            production: ProductionInfo(
                title: prefs.production,
                company: prefs.company,
                client: prefs.client
            ),
            source: SourceInfo(
                path: leftURL.path,
                originalName: leftURL.lastPathComponent,
                bytes: leftFolderInfo?.totalSize ?? 0,
                files: leftFolderInfo?.fileCount ?? 0,
                cameraDetected: "N/A"
            ),
            destination: DestinationInfo(
                path: rightURL.path,
                cameraLabel: "",
                labelPosition: "",
                separator: "",
                autoNumbered: false
            ),
            verification: VerificationInfo(
                method: verificationMode.rawValue,
                mode: "compare-folders",
                results: VerificationResults(
                    matched: matchCount,
                    mismatched: 0,
                    missing: 0,
                    extra: 0
                )
            ),
            performance: PerformanceInfo(
                duration: duration,
                throughput: "N/A",
                workers: workers
            )
        )
    }
}
