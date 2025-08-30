// SharedModels.swift - Unified models for both macOS and iPad
import Foundation
import SwiftUI

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

// MARK: - App Mode
enum AppMode: String, CaseIterable, Identifiable {
    case copyAndVerify = "Copy & Verify"
    case compareFolders = "Compare Folders" 
    case masterReport = "Master Report"
    
    var id: String { self.rawValue }
    
    var systemImage: String {
        switch self {
        case .copyAndVerify: return "doc.on.doc"
        case .compareFolders: return "folder.badge.questionmark"
        case .masterReport: return "doc.text.magnifyingglass"
        }
    }
    
    var description: String {
        switch self {
        case .copyAndVerify: return "Copy files and verify integrity"
        case .compareFolders: return "Compare two folders for differences"
        case .masterReport: return "Generate comprehensive transfer reports"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .copyAndVerify: return "Copy to Backups"
        case .compareFolders: return "Compare Folders"
        case .masterReport: return "Master Report"
        }
    }
    
    #if os(iOS)
    static var supportedModes: [AppMode] {
        return [.copyAndVerify, .compareFolders]
    }
    #endif
    
    #if os(macOS)
    static var supportedModes: [AppMode] {
        return AppMode.allCases
    }
    #endif
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
        case .quick: return "File size comparison only"
        case .standard: return "Basic checksum verification"
        case .thorough: return "Multiple checksum algorithms"
        case .paranoid: return "Byte-by-byte comparison + checksums"
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
    
    var checksumTypes: [ChecksumAlgorithm] {
        switch self {
        case .quick: return []
        case .standard: return [.sha256]
        case .thorough: return [.sha256, .md5]
        case .paranoid: return [.sha256, .md5, .sha1]
        }
    }
    
    func estimatedTime(fileCount: Int) -> String {
        let complexityFactor: Double
        switch self {
        case .standard: complexityFactor = 1.0
        case .thorough: complexityFactor = 1.8
        case .paranoid: complexityFactor = 2.5
        }
        
        let baseTimeMinutes = Double(fileCount) * 0.02 * complexityFactor
        
        if baseTimeMinutes < 1.0 {
            return "~\(Int(baseTimeMinutes * 60))s"
        } else if baseTimeMinutes < 60.0 {
            return "~\(Int(baseTimeMinutes))m"
        } else {
            let hours = Int(baseTimeMinutes / 60)
            let minutes = Int(baseTimeMinutes.truncatingRemainder(dividingBy: 60))
            return minutes > 0 ? "~\(hours)h \(minutes)m" : "~\(hours)h"
        }
    }
}

// MARK: - Checksum Types
enum ChecksumType: String, CaseIterable {
    case md5 = "MD5"
    case sha256 = "SHA-256"
    case sha1 = "SHA-1"
    
    var displayName: String { rawValue }
}

// MARK: - Operation State
enum OperationState {
    case notStarted
    case inProgress
    case completed
    case failed
    case cancelled
}

// MARK: - Completion State
enum CompletionState {
    case notStarted
    case inProgress
    case completed
    case failed
}

// MARK: - Progress Stage
enum ProgressStage {
    case idle
    case preparing
    case copying
    case verifying
    case generating
    case completed
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing..."
        case .copying: return "Copying files..."
        case .verifying: return "Verifying integrity..."
        case .generating: return "Generating reports..."
        case .completed: return "Complete"
        }
    }
}

// MARK: - Camera Label Settings
struct CameraLabelSettings: Codable {
    var label: String = ""
    var position: LabelPosition = .prefix
    var separator: Separator = .underscore
    var autoNumber: Bool = true
    var groupByCamera: Bool = false
    
    enum LabelPosition: String, CaseIterable, Codable {
        case prefix = "Prefix"
        case suffix = "Suffix"
    }
    
    enum Separator: String, CaseIterable, Codable {
        case underscore = "_"
        case dash = "-"
        case dot = "."
        case space = " "
        
        var displayName: String {
            switch self {
            case .underscore: return "Underscore (_)"
            case .dash: return "Dash (-)"
            case .dot: return "Dot (.)"
            case .space: return "Space ( )"
            }
        }
    }
}

// MARK: - Result Row
struct ResultRow: Identifiable {
    let id = UUID()
    let path: String
    let status: String
    let size: Int64
    let checksum: String?
    
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
    var notes: String = ""
    var makeReport: Bool = true
    var verifyWithChecksum: Bool = true
}

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

// MARK: - Folder Info
struct FolderInfo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileCount: Int
    let totalSize: Int64
    let lastModified: Date
    
    var name: String { url.lastPathComponent }
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    var formattedFileCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: fileCount)) ?? "\(fileCount)"
    }
    
    static func == (lhs: FolderInfo, rhs: FolderInfo) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Camera Type
enum CameraType: String, CaseIterable, Identifiable, Codable {
    case sony = "Sony"
    case canon = "Canon"
    case arri = "ARRI"
    case red = "RED"
    case blackmagic = "Blackmagic Design"
    case panasonic = "Panasonic"
    case fujifilm = "Fujifilm"
    case generic = "Generic"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .sony: return "Sony cameras (A7, FX series)"
        case .canon: return "Canon cameras (C series, EOS)"
        case .arri: return "ARRI professional cameras"
        case .red: return "RED digital cinema cameras"
        case .blackmagic: return "Blackmagic Design cameras"
        case .panasonic: return "Panasonic cameras (GH, EVA series)"
        case .fujifilm: return "Fujifilm cameras (X, GFX series)"
        case .generic: return "Generic or unknown camera type"
        }
    }
}

// MARK: - Camera Card Detection
struct CameraCard: Identifiable {
    let id = UUID()
    let name: String
    let manufacturer: String
    let model: String?
    let fileCount: Int
    let totalSize: Int64
    let detectionConfidence: Double
    let metadata: [String: Any]
    
    var displayName: String {
        if let model = model {
            return "\(manufacturer) \(model)"
        }
        return manufacturer
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
}

// MARK: - Operation Progress
struct OperationProgress {
    let overallProgress: Double
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int
    let currentStage: ProgressStage
    let speed: Double? // bytes per second
    let timeRemaining: TimeInterval?
    
    var formattedSpeed: String? {
        guard let speed = speed else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(speed)) + "/s"
    }
    
    var formattedTimeRemaining: String? {
        guard let timeRemaining = timeRemaining else { return nil }
        let minutes = Int(timeRemaining / 60)
        let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}