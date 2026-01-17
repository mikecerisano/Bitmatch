// ServiceProtocols.swift - Platform-agnostic service interfaces
import Foundation

// MARK: - File System Service Protocol
protocol FileSystemService {
    func selectSourceFolder() async -> URL?
    func selectDestinationFolders() async -> [URL]
    func selectLeftFolder() async -> URL?
    func selectRightFolder() async -> URL?
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
protocol ChecksumService {
    typealias ProgressCallback = (Double, String?) -> Void
    
    func generateChecksum(for fileURL: URL, type: ChecksumAlgorithm, progressCallback: ProgressCallback?) async throws -> String
    func verifyFileIntegrity(sourceURL: URL, destinationURL: URL, type: ChecksumAlgorithm, progressCallback: ProgressCallback?) async throws -> VerificationResult
    func performByteComparison(sourceURL: URL, destinationURL: URL, progressCallback: ProgressCallback?) async throws -> Bool
}

// MARK: - File Operations Service Protocol
protocol FileOperationsService {
    typealias ProgressCallback = (OperationProgress) -> Void
    
    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL], 
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64?,
        progressCallback: @escaping ProgressCallback,
        onFileResult: ((FileOperationResult) -> Void)?
    ) async throws -> FileOperation
    
    func cancelOperation()
    func pauseOperation() async
    func resumeOperation() async
}

// MARK: - Camera Detection Service Protocol
protocol CameraDetectionService {
    func detectCamera(from folderURL: URL) async -> CameraDetectionResult
    func analyzeFolderStructure(at url: URL) async throws -> [String: Any]
    func extractVideoMetadata(from fileURL: URL) async throws -> [String: Any]
    func parseXMLMetadata(from fileURL: URL) async throws -> [String: Any]
}

// MARK: - Platform Manager Protocol
protocol PlatformManager {
    nonisolated var fileSystem: FileSystemService { get }
    nonisolated var checksum: ChecksumService { get }
    nonisolated var fileOperations: FileOperationsService { get }
    nonisolated var cameraDetection: CameraDetectionService { get }
    nonisolated var supportsDragAndDrop: Bool { get }
    
    func presentAlert(title: String, message: String) async
    func presentError(_ error: Error) async
    func openURL(_ url: URL) async -> Bool
    
    // Background Task Management
    func beginBackgroundTask(name: String?, expirationHandler: (() -> Void)?) -> Int
    func endBackgroundTask(_ id: Int)
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
    
    var statusDescription: String {
        if success {
            if let verification = verificationResult {
                return verification.isValid ? "✅ Verified" : "⚠️ Checksum Mismatch"
            }
            return "✅ Copied"
        } else {
            return "❌ Failed"
        }
    }
}
