// EngineProtocols.swift - What the engine needs from the platform, and what it returns.
import Foundation

// MARK: - File Access (engine)

/// What the engine needs from the file system: access scopes, listing,
/// sizes, directory creation and free space. No pickers.
protocol FileAccess: Sendable {
    func validateFileAccess(url: URL) async -> Bool
    func startAccessing(url: URL) -> Bool
    func stopAccessing(url: URL)
    func getFileList(from folderURL: URL) async throws -> [URL]
    // NOTE: copyFile removed - all copying now goes through FileCopyService.copyAllSafely()
    // which provides atomic writes, resume support, and streaming enumeration
    nonisolated func getFileSize(for url: URL) throws -> Int64
    nonisolated func createDirectory(at url: URL) throws
    nonisolated func freeSpace(at url: URL) -> Int64
}

// MARK: - Checksum Service Protocol
protocol ChecksumService: Sendable {
    typealias ProgressCallback = @Sendable (Double, String?) -> Void
    
    func generateChecksum(for fileURL: URL, type: ChecksumAlgorithm, progressCallback: ProgressCallback?) async throws -> String
    func verifyFileIntegrity(sourceURL: URL, destinationURL: URL, type: ChecksumAlgorithm, progressCallback: ProgressCallback?) async throws -> VerificationResult
    func performByteComparison(sourceURL: URL, destinationURL: URL, progressCallback: ProgressCallback?) async throws -> Bool
}

// MARK: - File Operations Service Protocol
protocol FileOperationsService: Sendable {
    typealias ProgressCallback = @Sendable (OperationProgress) -> Void
    typealias FileResultCallback = @Sendable (FileOperationResult) async -> Void
    
    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL], 
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64?,
        progressCallback: @escaping ProgressCallback,
        onFileResult: FileResultCallback?
    ) async throws -> FileOperation
    
    func cancelOperation()
    func pauseOperation() async
    func resumeOperation() async
}

// MARK: - Shared Result Types

struct FileOperation {
    let id = UUID()
    let sourceURL: URL
    let destinationURLs: [URL]
    let startTime: Date
    var endTime: Date?
    let results: [FileOperationResult]
    let verificationMode: VerificationMode
    let settings: CameraLabelSettings
    let estimatedTotalBytes: Int64? // For improved ETA calculation
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

struct FileOperationResult {
    let sourceURL: URL
    let destinationURL: URL
    let success: Bool
    let error: Error?
    let fileSize: Int64
    let verificationResult: VerificationResult?
    let processingTime: TimeInterval
    
    var outcome: ResultOutcome {
        if let verification = verificationResult {
            return verification.isValid ? .verified : .checksumMismatch
        }
        return success ? .copiedUnverified : .failed
    }

    var statusDescription: String { outcome.statusText }
}
