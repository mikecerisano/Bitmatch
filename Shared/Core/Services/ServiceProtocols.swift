// ServiceProtocols.swift - Platform-agnostic service interfaces
import Foundation

// MARK: - File System Service Protocol
protocol FileSystemService {
    func selectSourceFolder() async -> URL?
    func selectDestinationFolders() async -> [URL]
    func selectLeftFolder() async -> URL?
    func selectRightFolder() async -> URL?
    func validateFileAccess(url: URL) async -> Bool
    func getFileList(from folderURL: URL) async throws -> [URL]
    func copyFile(from sourceURL: URL, to destinationURL: URL) async throws
    nonisolated func getFileSize(for url: URL) throws -> Int64
    nonisolated func createDirectory(at url: URL) throws
}

// MARK: - Checksum Service Protocol
protocol ChecksumService {
    typealias ProgressCallback = (Double, String?) -> Void
    
    func generateChecksum(for fileURL: URL, type: ChecksumType, progressCallback: ProgressCallback?) async throws -> String
    func verifyFileIntegrity(sourceURL: URL, destinationURL: URL, type: ChecksumType, progressCallback: ProgressCallback?) async throws -> VerificationResult
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
        progressCallback: @escaping ProgressCallback
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
    
    func presentAlert(title: String, message: String) async
    func presentError(_ error: Error) async
    func openURL(_ url: URL) async -> Bool
}

// MARK: - Shared Result Types
struct VerificationResult {
    let sourceChecksum: String
    let destinationChecksum: String
    let matches: Bool
    let checksumType: ChecksumType
    let processingTime: TimeInterval
    let fileSize: Int64
    
    var isValid: Bool { matches }
    
    var speedMBps: Double {
        guard processingTime > 0 else { return 0 }
        let sizeInMB = Double(fileSize) / (1024 * 1024)
        return sizeInMB / processingTime
    }
}

struct FileOperation {
    let id = UUID()
    let sourceURL: URL
    let destinationURLs: [URL]
    let startTime: Date
    var endTime: Date?
    let results: [FileOperationResult]
    let verificationMode: VerificationMode
    let settings: CameraLabelSettings
    
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

struct CameraDetectionResult {
    let cameraCard: CameraCard?
    let confidence: Double
    let metadata: [String: Any]
    let detectionMethod: String
    let processingTime: TimeInterval
    
    var isValid: Bool { confidence > 0.7 }
}

// MARK: - Error Types
enum BitMatchError: LocalizedError {
    case fileAccessDenied(URL)
    case fileNotFound(URL)
    case checksumMismatch(expected: String, actual: String)
    case operationCancelled
    case invalidURL(String)
    case platformNotSupported
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .fileAccessDenied(let url):
            return "Access denied for file: \(url.lastPathComponent)"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected: \(expected), Got: \(actual)"
        case .operationCancelled:
            return "Operation was cancelled by user"
        case .invalidURL(let path):
            return "Invalid file path: \(path)"
        case .platformNotSupported:
            return "This feature is not supported on this platform"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}