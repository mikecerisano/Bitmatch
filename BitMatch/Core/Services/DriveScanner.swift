// Core/Services/DriveScanner.swift
import Foundation

final class DriveScanner {
    
    static func scanForBitMatchReports(at rootURL: URL) async -> [TransferCard] {
        var transfers: [TransferCard] = []
        let fm = FileManager.default
        
        SharedLogger.info("Starting scan at: \(rootURL.path)", category: .transfer)
        
        // Get today's date for filtering
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Create enumerator for recursive search
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            SharedLogger.error("Failed to create enumerator for: \(rootURL.path)", category: .transfer)
            return []
        }
        
        var filesChecked = 0
        var reportsFound = 0
        
        // Search for BitMatchReport.json files
        while let fileURL = enumerator.nextObject() as? URL {
            filesChecked += 1
            
            let filename = fileURL.lastPathComponent
            // Check if this looks like a BitMatch report file
            if isReportFilename(filename) {
                do {
                    // Check if file was created today
                    let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    guard let modDate = resourceValues.contentModificationDate,
                          calendar.isDate(modDate, inSameDayAs: today) else {
                        continue
                    }

                    let fileSize = resourceValues.fileSize ?? 0
                    if fileSize > 20_000_000 {
                        SharedLogger.warning("Skipping oversized report \(filename) (\(fileSize) bytes)", category: .transfer)
                        continue
                    }

                    if let transfer = try parseTransferReport(at: fileURL) {
                        transfers.append(transfer)
                        reportsFound += 1
                        
                        SharedLogger.info("Found transfer: \(transfer.cameraName) at \(fileURL.path)", category: .transfer)
                    }
                } catch {
                    SharedLogger.error("Error processing report at \(fileURL.path): \(error)", category: .transfer)
                }
            }
            
            // Progress update every 1000 files
            if filesChecked % 1000 == 0 {
                SharedLogger.debug("Checked \(filesChecked) files, found \(reportsFound) reports", category: .transfer)
            }
        }
        
        SharedLogger.info("Scan completed: \(filesChecked) files checked, \(reportsFound) reports found", category: .transfer)
        return transfers.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Helper Methods
    
    private static func convertToTransferCard(report: EnhancedJSONReport, url: URL) -> TransferCard {
        let sourceURL = URL(fileURLWithPath: report.source.path)
        let destinationURLs = report.destinations.map { URL(fileURLWithPath: $0.path) }
        let cameraName = report.source.cameraDetected ?? extractCameraName(from: report, url: url)
        let verified = report.statistics.issues == 0

        let sourceFolderInfo = FolderInfo(
            url: sourceURL,
            fileCount: report.source.fileCount,
            totalSize: report.source.totalSize,
            lastModified: report.timestamp,
            isInternalDrive: isInternalDrive(sourceURL)
        )

        let destinationFolderInfos = destinationURLs.map { destURL in
            FolderInfo(
                url: destURL,
                fileCount: report.source.fileCount,
                totalSize: report.source.totalSize,
                lastModified: report.timestamp,
                isInternalDrive: isInternalDrive(destURL)
            )
        }

        let cameraMetadata: [String: Any] = [
            "reportPath": url.path,
            "reportTimestamp": report.timestamp
        ]

        let cameraCard = CameraCard(
            name: cameraName,
            manufacturer: detectManufacturer(from: cameraName),
            model: cameraName,
            fileCount: report.source.fileCount,
            totalSize: report.source.totalSize,
            detectionConfidence: report.source.cameraDetected != nil ? 0.95 : 0.6,
            metadata: cameraMetadata,
            volumeURL: sourceURL,
            cameraType: detectCameraType(from: cameraName),
            mediaPath: sourceURL
        )

        let transferMetadata = TransferMetadata(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            startTime: report.timestamp,
            endTime: report.timestamp.addingTimeInterval(report.performance.totalDuration),
            totalFiles: report.source.fileCount,
            totalSize: report.source.totalSize,
            verificationMode: verificationMode(from: report.verification),
            cameraSettings: nil
        )

        let completion = OperationCompletionInfo(
            success: verified,
            message: verified ? "Verified" : "\(report.statistics.issues) issues"
        )

        return TransferCard(
            source: sourceFolderInfo,
            destinations: destinationFolderInfos,
            cameraCard: cameraCard,
            metadata: transferMetadata,
            progress: 1.0,
            state: .completed(completion)
        )
    }
    
    private static func extractCameraName(from report: EnhancedJSONReport, url: URL) -> String {
        // First prefer the explicit source name if it looks camera-like
        let sourceURL = URL(fileURLWithPath: report.source.path)
        let candidateComponents = sourceURL.pathComponents + url.deletingLastPathComponent().pathComponents
        
        for component in candidateComponents.reversed() {
            let upper = component.uppercased()
            
            // Check for camera-like names
            if upper.contains("CAM") || upper.contains("CARD") || 
               upper.contains("A") || upper.contains("B") ||
               upper.contains("ALEXA") || upper.contains("RED") ||
               upper.contains("C100") || upper.contains("C300") {
                return component
            }
        }
        
        // Fall back to provided source name or folder name
        if !report.source.name.isEmpty {
            return report.source.name
        }
        return sourceURL.lastPathComponent.isEmpty ? "Unknown Camera" : sourceURL.lastPathComponent
    }

    private static func parseTransferReport(at url: URL) throws -> TransferCard? {
        try autoreleasepool {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let enhanced = try decoder.decode(EnhancedJSONReport.self, from: data)
                return convertToTransferCard(report: enhanced, url: url)
            } catch {
                SharedLogger.error("Failed to parse BitMatch report at \(url.path): \(error.localizedDescription)", category: .transfer)
                return nil
            }
        }
    }

    private static func isReportFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower == "bitmatchreport.json" || lower == "bitmatch_report.json" {
            return true
        }
        if lower.hasPrefix("bitmatch_report_") && lower.hasSuffix(".json") {
            return true
        }
        if lower.hasSuffix("_report.json") && lower.contains("bitmatch") {
            return true
        }
        return false
    }

    private static func verificationMode(from verification: EnhancedJSONReport.Verification) -> VerificationMode {
        switch verification.method.lowercased() {
        case "quick": return .quick
        case "thorough": return .thorough
        case "paranoid": return .paranoid
        case "checksum":
            if let algorithm = verification.algorithm?.lowercased(), algorithm.contains("md5") {
                return .thorough
            }
            return .standard
        case "byte-to-byte", "byte-compare", "byte_compare": return .paranoid
        default: return .standard
        }
    }

    private static func detectManufacturer(from cameraName: String) -> String {
        let upper = cameraName.uppercased()
        if upper.contains("SONY") || upper.contains("FX") || upper.contains("A7") {
            return "Sony"
        } else if upper.contains("CANON") || upper.contains("C70") || upper.contains("C100") {
            return "Canon"
        } else if upper.contains("RED") || upper.contains("DRAGON") {
            return "RED"
        } else if upper.contains("ARRI") || upper.contains("ALEXA") {
            return "ARRI"
        } else if upper.contains("BLACKMAGIC") || upper.contains("URSA") {
            return "Blackmagic"
        } else if upper.contains("DJI") {
            return "DJI"
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
        } else if upper.contains("SONY") && upper.contains("A7") {
            return .sonyA7S
        } else if upper.contains("CANON") && upper.contains("C70") {
            return .canonC70
        } else if upper.contains("CANON") {
            return .canon
        } else if upper.contains("ARRI") || upper.contains("ALEXA") {
            return .arriAlexa
        } else if upper.contains("RED") {
            return .redCamera
        } else if upper.contains("BLACKMAGIC") {
            return .blackmagic
        } else if upper.contains("GOPRO") {
            return .gopro
        } else if upper.contains("DJI") {
            return .dji
        } else {
            return .generic
        }
    }

    private static func isInternalDrive(_ url: URL) -> Bool {
        !url.path.hasPrefix("/Volumes/")
    }
}
