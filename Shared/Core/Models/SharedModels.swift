// SharedModels.swift - Core shared models for both macOS and iPad
import Foundation
import SwiftUI

// Import specialized model files
// These imports make all models available throughout the app
// while keeping the code organized in focused files

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
        case .quick: complexityFactor = 0.5
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





// MARK: - Folder Info
struct FolderInfo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileCount: Int
    let totalSize: Int64
    let lastModified: Date
    let isInternalDrive: Bool
    
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

// MARK: - Enhanced Folder Info
struct EnhancedFolderInfo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileCount: Int
    let totalSize: Int64
    let lastModified: Date
    let isInternalDrive: Bool
    
    // Enhanced metadata
    let fileTypeBreakdown: [String: Int] // File extension -> count
    let largestFile: (name: String, size: Int64)?
    let oldestFileDate: Date?
    let newestFileDate: Date?
    
    var name: String { url.lastPathComponent }
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    var formattedFileCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: fileCount)) ?? "\(fileCount)"
    }
    
    var topFileTypes: [(type: String, count: Int)] {
        Array(fileTypeBreakdown.sorted { $0.value > $1.value }.prefix(3))
            .map { (type: $0.key, count: $0.value) }
    }
    
    var averageFileSize: Int64 {
        fileCount > 0 ? totalSize / Int64(fileCount) : 0
    }
    
    var formattedAverageFileSize: String {
        ByteCountFormatter.string(fromByteCount: averageFileSize, countStyle: .file)
    }
    
    var formattedLargestFile: String {
        guard let largest = largestFile else { return "No files" }
        let size = ByteCountFormatter.string(fromByteCount: largest.size, countStyle: .file)
        return "\(largest.name) (\(size))"
    }
    
    var dateRangeDescription: String {
        guard let oldest = oldestFileDate, let newest = newestFileDate else {
            return "No date info"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        
        if Calendar.current.isDate(oldest, inSameDayAs: newest) {
            return "All from \(formatter.string(from: oldest))"
        } else {
            return "\(formatter.string(from: oldest)) - \(formatter.string(from: newest))"
        }
    }
    
    static func == (lhs: EnhancedFolderInfo, rhs: EnhancedFolderInfo) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Drive Type
enum DriveType {
    case internalDrive
    case externalDrive
    case cameraCard
    case networkDrive
    case unknown
    
    var displayName: String {
        switch self {
        case .internalDrive: return "Internal Drive"
        case .externalDrive: return "External Drive"
        case .cameraCard: return "Camera Card"
        case .networkDrive: return "Network Drive"
        case .unknown: return "Unknown Drive"
        }
    }
    
    var systemImage: String {
        switch self {
        case .internalDrive: return "internaldrive"
        case .externalDrive: return "externaldrive"
        case .cameraCard: return "sdcard"
        case .networkDrive: return "network"
        case .unknown: return "questionmark.square.dashed"
        }
    }
    
    var color: Color {
        switch self {
        case .internalDrive: return .blue
        case .externalDrive: return .green
        case .cameraCard: return .orange
        case .networkDrive: return .purple
        case .unknown: return .gray
        }
    }
}

// MARK: - Folder Display Info
struct FolderDisplayInfo {
    let baseInfo: FolderInfo
    let driveType: DriveType
    let availableSpace: Int64?
    let isLoading: Bool
    
    // If enhanced details are needed, obtain via coordinator helpers.
    
    var formattedAvailableSpace: String? {
        guard let space = availableSpace else { return nil }
        return ByteCountFormatter.string(fromByteCount: space, countStyle: .file)
    }
    
    var spaceUtilizationWarning: String? {
        guard let available = availableSpace else { return nil }
        
        let requiredSpace = baseInfo.totalSize
        let utilizationRatio = Double(requiredSpace) / Double(available)
        
        if utilizationRatio > 0.9 {
            return "⚠️ Low disk space"
        } else if utilizationRatio > 0.7 {
            return "⚡ Limited space"
        }
        return nil
    }
    
    var professionalSummary: String {
        let parts = [
            baseInfo.formattedFileCount + " files",
            baseInfo.formattedSize,
            driveType.displayName
        ]
        
        if let warning = spaceUtilizationWarning {
            return parts.joined(separator: " • ") + " • \(warning)"
        } else {
            return parts.joined(separator: " • ")
        }
    }
}

// MARK: - Notifications
extension NSNotification.Name {
    static let cameraCardDetected = NSNotification.Name("cameraCardDetected")
    static let showPreferences = NSNotification.Name("showPreferences")
    static let fakeTransferQueued = NSNotification.Name("fakeTransferQueued")
    static let simulateTransferCompletion = NSNotification.Name("simulateTransferCompletion")
    static let operationCancelledByUser = NSNotification.Name("operationCancelledByUser")
    static let operationCompleted = NSNotification.Name("operationCompleted")
}

// MARK: - FolderInfo Compatibility Extension
extension EnhancedFolderInfo {
    /// Convert to base FolderInfo for backward compatibility
    var asFolderInfo: FolderInfo {
        return FolderInfo(
            url: url,
            fileCount: fileCount,
            totalSize: totalSize,
            lastModified: lastModified,
            isInternalDrive: isInternalDrive
        )
    }
}
