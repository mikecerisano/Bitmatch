// Core/Services/DriveScanner.swift
import Foundation

final class DriveScanner {
    
    static func scanForBitMatchReports(at rootURL: URL) async -> [TransferCard] {
        var transfers: [TransferCard] = []
        let fm = FileManager.default
        
        print("Starting scan at: \(rootURL.path)")
        
        // Get today's date for filtering
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Create enumerator for recursive search
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("Failed to create enumerator for: \(rootURL.path)")
            return []
        }
        
        var filesChecked = 0
        var reportsFound = 0
        
        // Search for BitMatchReport.json files
        while let fileURL = enumerator.nextObject() as? URL {
            filesChecked += 1
            
            // Check if this is a BitMatchReport.json file
            if fileURL.lastPathComponent == "BitMatchReport.json" {
                do {
                    // Check if file was created today
                    let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                    if let modDate = resourceValues.contentModificationDate,
                       calendar.isDate(modDate, inSameDayAs: today) {
                        
                        // Read and parse the JSON report
                        let data = try Data(contentsOf: fileURL)
                        let report = try JSONDecoder().decode(EnhancedJSONReport.self, from: data)
                        
                        // Convert to TransferCard
                        let transfer = convertToTransferCard(report: report, url: fileURL)
                        transfers.append(transfer)
                        reportsFound += 1
                        
                        print("Found transfer: \(transfer.cameraName) at \(fileURL.path)")
                    }
                } catch {
                    print("Error processing report at \(fileURL.path): \(error)")
                }
            }
            
            // Progress update every 1000 files
            if filesChecked % 1000 == 0 {
                print("Checked \(filesChecked) files, found \(reportsFound) reports")
            }
        }
        
        print("Scan completed: \(filesChecked) files checked, \(reportsFound) reports found")
        return transfers.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Helper Methods
    
    private static func convertToTransferCard(report: EnhancedJSONReport, url: URL) -> TransferCard {
        // Extract camera name from folder structure or use detected camera
        let cameraName = report.source.cameraDetected ?? extractCameraName(from: report, url: url)
        
        // Determine if transfer was verified (has matches and no issues)
        let verified = report.statistics.matches > 0 && report.statistics.issues == 0
        
        return TransferCard(
            cameraName: cameraName,
            cameraIcon: iconForCamera(cameraName),
            totalSize: report.source.totalSize,
            fileCount: report.source.fileCount,
            rolls: 1, // Single roll per report
            sourcePath: report.source.path,
            destinationPaths: report.destinations.map { $0.path },
            timestamp: report.timestamp,
            verified: verified,
            metadata: nil // Could be enhanced later
        )
    }
    
    private static func extractCameraName(from report: EnhancedJSONReport, url: URL) -> String {
        // Try to extract camera name from folder structure
        let pathComponents = url.pathComponents
        
        // Look for common camera patterns in the path
        for component in pathComponents.reversed() {
            let upper = component.uppercased()
            
            // Check for camera-like names
            if upper.contains("CAM") || upper.contains("CARD") || 
               upper.contains("A") || upper.contains("B") ||
               upper.contains("ALEXA") || upper.contains("RED") ||
               upper.contains("C100") || upper.contains("C300") {
                return component
            }
        }
        
        // Fall back to source folder name
        return URL(fileURLWithPath: report.source.path).lastPathComponent
    }
    
    private static func iconForCamera(_ camera: String) -> String {
        let upper = camera.uppercased()
        
        if upper.contains("ALEXA") || upper.contains("RED") || upper.contains("ARRI") {
            return "film"
        } else if upper.contains("DRONE") || upper.contains("DJI") {
            return "airplane"
        } else if upper.contains("GOPRO") {
            return "video.circle"
        } else if upper.contains("AUDIO") {
            return "waveform"
        } else {
            return "camera.fill"
        }
    }
}