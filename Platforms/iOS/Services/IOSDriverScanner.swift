// IOSDriverScanner.swift - iOS-specific drive scanning and report discovery
import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
class IOSDriverScanner: NSObject {
    
    // MARK: - Drive Selection and Scanning
    
    /// Present drive/folder selection UI and scan for BitMatch reports
    static func selectDriveAndScan() async -> [TransferCard] {
        SharedLogger.info("Starting iOS drive selection for Master Report scanning...")

        // Present folder picker for drive selection
        guard let selectedURL = await presentDriveSelector() else {
            SharedLogger.info("Drive selection cancelled")
            return []
        }

        SharedLogger.info("Selected drive: \(selectedURL.path)")
        
        // Ensure we have access to the selected location
        guard selectedURL.startAccessingSecurityScopedResource() else {
            SharedLogger.error("Failed to access security scoped resource")
            return []
        }
        
        defer {
            selectedURL.stopAccessingSecurityScopedResource()
        }
        
        // Scan the selected drive for BitMatch reports
        return await scanForBitMatchReports(at: selectedURL)
    }
    
    /// Get available drives/volumes for selection
    static func getAvailableVolumes() -> [VolumeInfo] {
        var volumes: [VolumeInfo] = []
        
        // On iOS, we mainly work with app sandbox and external storage
        let fileManager = FileManager.default
        
        // Document directory (internal)
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            volumes.append(VolumeInfo(
                name: "Documents",
                path: documentsURL.path,
                url: documentsURL,
                isExternal: false,
                isRemovable: false,
                volumeType: .`internal`
            ))
        }
        
        // Try to detect external storage through mounted volumes
        // Note: On iOS, access to external drives is limited to document picker
        let mountedVolumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey
        ], options: [])
        
        for volumeURL in mountedVolumes ?? [] {
            do {
                let resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeIsRemovableKey,
                    .volumeIsInternalKey
                ])
                
                let name = resourceValues.volumeName ?? volumeURL.lastPathComponent
                let isRemovable = resourceValues.volumeIsRemovable ?? false
                let isInternal = resourceValues.volumeIsInternal ?? true
                
                // Only add external/removable volumes for scanning
                if !isInternal || isRemovable {
                    volumes.append(VolumeInfo(
                        name: name,
                        path: volumeURL.path,
                        url: volumeURL,
                        isExternal: !isInternal,
                        isRemovable: isRemovable,
                        volumeType: isRemovable ? .removable : .external
                    ))
                }
            } catch {
                SharedLogger.error("Error reading volume info for \(volumeURL): \(error)")
            }
        }

        SharedLogger.info("Found \(volumes.count) available volumes")
        return volumes
    }
    
    // MARK: - BitMatch Report Scanning
    
    /// Scan a drive/folder for BitMatch reports (same logic as macOS but iOS-optimized)
    static func scanForBitMatchReports(at rootURL: URL) async -> [TransferCard] {
        SharedLogger.info("Starting BitMatch report scan at: \(rootURL.path)")
        var transfers: [TransferCard] = []
        let fileManager = FileManager.default
        
        // Get today's date for filtering recent reports
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        
        // Create enumerator with iOS-appropriate options
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            SharedLogger.error("Failed to create enumerator for: \(rootURL.path)")
            return []
        }
        
        var filesScanned = 0
        var reportsFound = 0
        let maxFilesToScan = 50000 // iOS performance limit
        
        while let fileURL = enumerator.nextObject() as? URL {
            filesScanned += 1
            
            // iOS performance protection - limit scanning
            if filesScanned > maxFilesToScan {
                SharedLogger.warning("Reached scanning limit of \(maxFilesToScan) files")
                break
            }
            
            // Look for BitMatch report files
            let filename = fileURL.lastPathComponent
            if filename == "BitMatchReport.json" || filename.hasSuffix("_Report.json") {
                do {
                    // Check if file was modified recently (within last 2 days)
                    let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    
                    if let modDate = resourceValues.contentModificationDate,
                       modDate >= twoDaysAgo {
                        
                        // Ensure file is not too large (iOS memory protection)
                        let fileSize = resourceValues.fileSize ?? 0
                        if fileSize < 10_000_000 { // 10MB limit
                            
                            // Read and parse the JSON report
                            let data = try Data(contentsOf: fileURL)
                            
                            if let transfer = try? parseReportToTransferCard(data: data, reportURL: fileURL) {
                                transfers.append(transfer)
                                reportsFound += 1
                                SharedLogger.info("Found transfer: \(transfer.cameraName) at \(fileURL.path)")
                            }
                        } else {
                            SharedLogger.debug("Skipping large file: \(filename) (\(fileSize) bytes)")
                        }
                    }
                } catch {
                    SharedLogger.error("Error processing report at \(fileURL.path): \(error)")
                }
            }

            // Progress update for iOS
            if filesScanned % 500 == 0 {
                SharedLogger.debug("Scanned \(filesScanned) files, found \(reportsFound) reports")
                
                // Yield to main thread for UI responsiveness
                await Task.yield()
            }
        }

        SharedLogger.info("Scan completed: \(filesScanned) files scanned, \(reportsFound) reports found")
        return transfers.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Private Helper Methods
    
    private static func presentDriveSelector() async -> URL? {
        return await withCheckedContinuation { continuation in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            
            let delegate = DrivePickerDelegate { url in
                continuation.resume(returning: url)
            }
            picker.delegate = delegate
            
            // Present the picker
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                
                // Configure for iPad if needed
                if UIDevice.current.userInterfaceIdiom == .pad {
                    picker.modalPresentationStyle = .formSheet
                }
                
                rootViewController.present(picker, animated: true)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
    
    private static func parseReportToTransferCard(data: Data, reportURL: URL) throws -> TransferCard? {
        // Try parsing as EnhancedJSONReport first (current format)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let enhancedReport: EnhancedJSONReport = try? decoder.decode(EnhancedJSONReport.self, from: data) {
            return convertEnhancedReportToTransferCard(enhancedReport, reportURL: reportURL)
        }
        
        // Try parsing as legacy format if needed
        if let legacyReport = try? parseLegacyReport(data: data) {
            return convertLegacyReportToTransferCard(legacyReport, reportURL: reportURL)
        }

        SharedLogger.warning("Unable to parse report format at \(reportURL.path)")
        return nil
    }
    
    private static func convertEnhancedReportToTransferCard(_ report: EnhancedJSONReport, reportURL: URL) -> TransferCard {
        // Extract camera name
        let cameraName = report.source.cameraDetected ?? extractCameraNameFromPath(report.source.path)
        
        // Determine verification status
        let verified = report.statistics.matches > 0 && report.statistics.issues == 0
        
        // Create source FolderInfo
        let sourceFolderInfo = FolderInfo(
            url: URL(fileURLWithPath: report.source.path),
            fileCount: report.source.fileCount,
            totalSize: report.source.totalSize,
            lastModified: report.timestamp,
            isInternalDrive: !report.source.path.contains("/Volumes/")
        )
        
        // Create destination FolderInfos
        let destinationFolderInfos = report.destinations.map { dest in
            FolderInfo(
                url: URL(fileURLWithPath: dest.path),
                fileCount: report.source.fileCount, // Use source count as approximation
                totalSize: report.source.totalSize,
                lastModified: report.timestamp,
                isInternalDrive: !dest.path.contains("/Volumes/")
            )
        }
        
        // Create camera card info
        let cameraCard = CameraCard(
            name: cameraName,
            manufacturer: extractManufacturer(from: cameraName),
            model: cameraName,
            fileCount: report.source.fileCount,
            totalSize: report.source.totalSize,
            detectionConfidence: report.source.cameraDetected != nil ? 0.9 : 0.5,
            metadata: ["reportPath": reportURL.path],
            volumeURL: URL(fileURLWithPath: report.source.path),
            cameraType: detectCameraType(from: cameraName),
            mediaPath: URL(fileURLWithPath: report.source.path)
        )
        
        return TransferCard(
            source: sourceFolderInfo,
            destinations: destinationFolderInfos,
            cameraCard: cameraCard,
            metadata: TransferMetadata(
                sourceURL: URL(fileURLWithPath: report.source.path),
                destinationURLs: report.destinations.map { URL(fileURLWithPath: $0.path) },
                startTime: report.timestamp,
                endTime: Calendar.current.date(byAdding: .second, value: Int(report.performance.totalDuration), to: report.timestamp),
                totalFiles: report.source.fileCount,
                totalSize: report.source.totalSize,
                verificationMode: .standard,
                cameraSettings: nil
            ),
            progress: verified ? 1.0 : 0.8,
            state: verified ? .completed(OperationCompletionInfo(success: true, message: "Verified")) : .completed(OperationCompletionInfo(success: false, message: "Issues found"))
        )
    }
    
    private static func parseLegacyReport(data: Data) throws -> LegacyReportFormat? {
        // Implement legacy report parsing if needed
        return nil
    }
    
    private static func convertLegacyReportToTransferCard(_ report: LegacyReportFormat, reportURL: URL) -> TransferCard {
        // Implement legacy conversion if needed
        return TransferCard(
            source: FolderInfo(url: reportURL, fileCount: 0, totalSize: 0, lastModified: Date(), isInternalDrive: true),
            destinations: [],
            cameraCard: nil,
            metadata: nil,
            progress: 0,
            state: .idle
        )
    }
    
    private static func extractCameraNameFromPath(_ path: String) -> String {
        let pathComponents = path.components(separatedBy: "/")
        
        // Look for camera-like patterns
        for component in pathComponents.reversed() {
            let upper = component.uppercased()
            if upper.contains("CAM") || upper.contains("CARD") ||
               upper.contains("ALEXA") || upper.contains("RED") ||
               upper.contains("SONY") || upper.contains("CANON") ||
               upper.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCD")) != nil {
                return component
            }
        }
        
        return pathComponents.last ?? "Unknown Camera"
    }
    
    private static func extractManufacturer(from cameraName: String) -> String {
        let upper = cameraName.uppercased()
        
        if upper.contains("SONY") || upper.contains("FX") || upper.contains("A7") {
            return "Sony"
        } else if upper.contains("CANON") || upper.contains("C70") || upper.contains("C100") {
            return "Canon"
        } else if upper.contains("RED") || upper.contains("DRAGON") {
            return "RED"
        } else if upper.contains("ALEXA") || upper.contains("ARRI") {
            return "ARRI"
        } else if upper.contains("GOPRO") {
            return "GoPro"
        } else {
            return "Unknown"
        }
    }
    
    private static func detectCameraType(from cameraName: String) -> CameraType {
        let upper = cameraName.uppercased()
        
        if upper.contains("SONY") && upper.contains("FX6") {
            return .sonyFX6
        } else if upper.contains("SONY") && upper.contains("FX3") {
            return .sonyFX3
        } else if upper.contains("SONY") && upper.contains("A7S") {
            return .sonyA7S
        } else if upper.contains("CANON") && upper.contains("C70") {
            return .canonC70
        } else if upper.contains("RED") {
            return .red
        } else if upper.contains("ALEXA") || upper.contains("ARRI") {
            return .arri
        } else if upper.contains("GOPRO") {
            return .gopro
        } else if upper.contains("SONY") {
            return .sony
        } else if upper.contains("CANON") {
            return .canon
        } else {
            return .generic
        }
    }
}

// MARK: - Supporting Types

struct VolumeInfo {
    let name: String
    let path: String
    let url: URL
    let isExternal: Bool
    let isRemovable: Bool
    let volumeType: VolumeType
    
    enum VolumeType {
        case `internal`
        case external
        case removable
        case network
    }
}

struct LegacyReportFormat {
    // Define legacy report structure if needed
}

// Minimal representation of the enhanced JSON report used by BitMatch
// This mirrors the fields needed for TransferCard conversion
struct EnhancedJSONReport: Decodable {
    let timestamp: Date
    let source: SourceInfo
    let destinations: [DestinationInfo]
    let statistics: Statistics
    let performance: Performance

    struct SourceInfo: Decodable {
        let path: String
        let name: String?
        let totalSize: Int64
        let fileCount: Int
        let cameraDetected: String?
    }

    struct DestinationInfo: Decodable {
        let path: String
    }

    struct Statistics: Decodable {
        let totalFiles: Int?
        let totalBytes: Int64?
        let matches: Int
        let issues: Int
    }

    struct Performance: Decodable {
        let totalDuration: Double
    }
}

// MARK: - Document Picker Delegate for Drive Selection

private class DrivePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void
    
    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
