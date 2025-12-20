// TransferModels.swift - Transfer and reporting models
import Foundation

// MARK: - Transfer Metadata
struct TransferMetadata: Codable {
    let sourceURL: URL
    let destinationURLs: [URL]
    let startTime: Date
    let endTime: Date?
    let totalFiles: Int
    let totalSize: Int64
    let verificationMode: VerificationMode
    let cameraSettings: CameraLabelSettings?
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Transfer Card
struct TransferCard: Identifiable {
    let id = UUID()
    let source: FolderInfo
    let destinations: [FolderInfo]
    let cameraCard: CameraCard?
    let metadata: TransferMetadata?
    let progress: Double
    let state: OperationState
    
    var cameraName: String {
        return cameraCard?.name ?? "Unknown Camera"
    }
    
    var totalSize: Int64 {
        return source.totalSize
    }
    
    var fileCount: Int {
        return source.fileCount
    }
    
    var timestamp: Date {
        return metadata?.startTime ?? Date()
    }
    
    var verified: Bool {
        switch state {
        case .completed:
            return true
        default:
            return false
        }
    }
    
    var sourcePath: String {
        return source.url.path
    }
    
    var destinationPaths: [String] {
        return destinations.map { $0.url.path }
    }
    
    var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
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
}

// MARK: - Report Preferences  
struct ReportPrefs: Codable {
    var generatePDF: Bool = true
    var generateCSV: Bool = true
    var includeThumbnails: Bool = false
    var clientName: String = ""
    var projectName: String = ""
    var production: String = ""
    var company: String = ""
    var notes: String = ""
    var makeReport: Bool = true
    var verifyWithChecksum: Bool = true
    var enableAutoCameraDetection: Bool = true
    var autoPopulateSource: Bool = true
    var showCameraDetectionNotifications: Bool = true
    var checksumAlgorithm: ChecksumAlgorithm = .sha256
}
