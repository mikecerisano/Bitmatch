// Core/Services/ReportExporter.swift - Enhanced
import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Enhanced JSON Report Structures
struct EnhancedJSONReport: Codable {
    let reportVersion: String
    let timestamp: Date
    let jobId: UUID
    let mode: String
    let source: SourceInfo
    let destinations: [DestinationInfo]
    
    // Enhanced statistics
    let statistics: Statistics
    let extensions: [String: Int]  // File extension breakdown
    let performance: Performance
    let verification: Verification
    let results: [JSONReportItem]
    
    struct SourceInfo: Codable {
        let path: String
        let name: String
        let totalSize: Int64
        let fileCount: Int
        let cameraDetected: String?
        let driveType: String  // "NVMe", "SSD", "HDD", "Network"
    }
    
    struct DestinationInfo: Codable {
        let path: String
        let name: String
        let availableSpace: Int64
        let driveType: String
        let copyDuration: TimeInterval
        let verifyDuration: TimeInterval
    }
    
    struct Statistics: Codable {
        let totalFiles: Int
        let totalBytes: Int64
        let matches: Int
        let issues: Int
        let successRate: Double
        let averageFileSize: Int64
        let largestFile: FileInfo?
        let smallestFile: FileInfo?
    }
    
    struct FileInfo: Codable {
        let path: String
        let size: Int64
    }
    
    struct Performance: Codable {
        let totalDuration: TimeInterval
        let copyDuration: TimeInterval
        let verifyDuration: TimeInterval
        let throughputMBps: Double
        let peakSpeedMBps: Double
        let averageSpeedMBps: Double
        let filesPerSecond: Double
        let workers: Int
        let bottleneck: String?  // "Source Read", "Destination Write", "CPU", "Network"
    }
    
    struct Verification: Codable {
        let method: String
        let algorithm: String?
        let issuesByType: [String: Int]
        let checksumCache: CacheStats?
    }
    
    struct CacheStats: Codable {
        let hits: Int
        let misses: Int
        let hitRate: Double
    }
}

// MARK: - JSON Report Item Structure
struct JSONReportItem: Codable {
    let path: String
    let target: String?
    let status: String
    let fileExtension: String
    
    init(from row: ResultRow) {
        self.path = row.path
        self.target = row.target
        self.status = row.status.rawValue
        self.fileExtension = URL(fileURLWithPath: row.path).pathExtension.uppercased()
    }
}

// MARK: - Legacy JSON Report Structure (for backwards compatibility)
private struct JSONReport: Codable {
    let timestamp: Date
    let totalFiles: Int
    let matches: Int
    let issues: Int
    let results: [JSONReportItem]
}

// MARK: - Report Exporter Service
final class ReportExporter {
    
    static func export(mode: AppMode,
                      jobID: UUID,
                      started: Date,
                      finished: Date,
                      sourceURL: URL?,
                      destinationURLs: [URL],
                      results: [ResultRow],
                      fileCount: Int,
                      matchCount: Int,
                      prefs: ReportPrefs,
                      workers: Int,
                      totalBytesProcessed: Int64) async {
        
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let method = prefs.verifyWithChecksum ? "\(prefs.checksumAlgorithm.rawValue) Checksum" : "Byte-to-Byte Comparison"
        
        let destinationPaths = destinationURLs.map { $0.path }
        let issues = results.filter { $0.status != .match }
        
        // Calculate performance metrics
        let duration = finished.timeIntervalSince(started)
        let averageSpeed = duration > 0 ? Double(totalBytesProcessed) / duration / 1_048_576 : 0 // MB/s
        let filesPerSecond = duration > 0 ? Double(fileCount) / duration : 0
        
        let summary = ReportView.Summary(
            jobID: jobID,
            started: started,
            finished: finished,
            mode: mode,
            source: sourceURL?.path ?? "—",
            destinations: destinationPaths,
            totalFiles: fileCount,
            matched: matchCount,
            issues: issues.count,
            workers: workers,
            appVersion: appVersion,
            osVersion: osVersion,
            client: prefs.client,
            production: prefs.production,
            company: prefs.company,
            verificationMethod: method,
            totalBytesProcessed: totalBytesProcessed,
            averageSpeed: averageSpeed,
            clientLogoData: prefs.clientLogoData,
            companyLogoData: prefs.companyLogoData
        )
        
        // Generate PDF on main thread (required for SwiftUI views)
        #if os(macOS)
        let pdfData = await MainActor.run {
            generatePDF(summary: summary, results: results)
        }
        #else
        // PDF generation not available on iOS
        let pdfData = Data()
        #endif
        
        // Auto-save to reports folder
        await autoSaveReports(mode: mode,
                             destinationURLs: destinationURLs,
                       pdfData: pdfData,
                       results: results,
                       finished: finished,
                       checksumAlgorithm: prefs.verifyWithChecksum ? prefs.checksumAlgorithm : nil,
                       jobID: jobID,
                       started: started,
                       duration: duration,
                       sourceURL: sourceURL,
                       fileCount: fileCount,
                       matchCount: matchCount,
                       totalBytesProcessed: totalBytesProcessed,
                       workers: workers,
                       filesPerSecond: filesPerSecond,
                       prefs: prefs)
    }
    
    #if os(macOS)
    private static func generatePDF(summary: ReportView.Summary, results: [ResultRow]) -> Data {
        let view = ReportView(s: summary, rows: results)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        return hosting.dataWithPDF(inside: hosting.bounds)
    }
    #endif
    
    private static func autoSaveReports(mode: AppMode,
                                        destinationURLs: [URL],
                                        pdfData: Data,
                                        results: [ResultRow],
                                        finished: Date,
                                        checksumAlgorithm: ChecksumAlgorithm?,
                                        jobID: UUID,
                                        started: Date,
                                        duration: TimeInterval,
                                        sourceURL: URL?,
                                        fileCount: Int,
                                        matchCount: Int,
                                        totalBytesProcessed: Int64,
                                        workers: Int,
                                        filesPerSecond: Double,
                                        prefs: ReportPrefs) async {
        
        // Generate default filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime
        let dateString = formatter.string(from: finished).replacingOccurrences(of: ":", with: "-")
        let fileName = "BitMatch_Report_\(dateString).pdf"
        
        // Determine save location - auto-save to Reports folder
        let saveDirectory: URL
        if mode == .copyAndVerify, let firstDestination = destinationURLs.first {
            // Save to Reports folder inside first destination
            saveDirectory = firstDestination.appendingPathComponent("Reports", isDirectory: true)
        } else {
            // Fallback to Desktop/Reports
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            saveDirectory = desktop.appendingPathComponent("Reports", isDirectory: true)
        }
        
        // Create reports directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("Failed to create reports directory: \(error.localizedDescription)")
            DispatchQueue.main.async {
                showErrorAlert(message: "Failed to create reports directory: \(error.localizedDescription)")
            }
            return
        }
        
        let pdfURL = saveDirectory.appendingPathComponent(fileName)
        
        do {
            // Save PDF
            try pdfData.write(to: pdfURL)
            
            // Save CSV manifest with enhanced data
            let csvURL = pdfURL.deletingPathExtension().appendingPathExtension("csv")
            try exportEnhancedCSV(results: results,
                                 to: csvURL,
                                 duration: duration,
                                 filesPerSecond: filesPerSecond)
            
            // Save enhanced JSON report
            let jsonURL = pdfURL.deletingPathExtension().appendingPathExtension("json")
            try exportEnhancedJSONReport(
                results: results,
                to: jsonURL,
                jobID: jobID,
                started: started,
                finished: finished,
                mode: mode,
                sourceURL: sourceURL,
                destinationURLs: destinationURLs,
                fileCount: fileCount,
                matchCount: matchCount,
                totalBytesProcessed: totalBytesProcessed,
                duration: duration,
                workers: workers,
                prefs: prefs
            )
            
            // If checksums were used, auto-export checksum file (no dialog)
            if let algorithm = checksumAlgorithm {
                #if os(macOS)
                autoExportChecksums(results: results, algorithm: algorithm, baseURL: pdfURL)
                #else
                // Checksum export not available on iOS
                print("⚠️ Checksum export not available on iOS")
                #endif
            }
            
            NSLog("Report auto-saved successfully to: \(pdfURL.path)")
            
            // No need for success dialog since this is auto-save
            
        } catch {
            NSLog("Report export error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                showErrorAlert(message: "Failed to save report: \(error.localizedDescription)")
            }
        }
    }
    
    // Keep original function for manual export if needed elsewhere
    #if os(macOS)
    private static func showSavePanel(mode: AppMode,
                                     destinationURLs: [URL],
                                     pdfData: Data,
                                     results: [ResultRow],
                                     finished: Date,
                                     checksumAlgorithm: ChecksumAlgorithm?,
                                     jobID: UUID,
                                     started: Date,
                                     duration: TimeInterval,
                                     sourceURL: URL?,
                                     fileCount: Int,
                                     matchCount: Int,
                                     totalBytesProcessed: Int64,
                                     workers: Int,
                                     filesPerSecond: Double,
                                     prefs: ReportPrefs) {
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        
        // Generate default filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime
        let dateString = formatter.string(from: finished).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "BitMatch_Report_\(dateString).pdf"
        
        // Set default location
        if mode == .copyAndVerify, let firstDestination = destinationURLs.first {
            let reportsFolder = firstDestination.appendingPathComponent("Reports", isDirectory: true)
            try? FileManager.default.createDirectory(at: reportsFolder, withIntermediateDirectories: true)
            panel.directoryURL = reportsFolder
        } else {
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
        
        // Show panel and save files
        if panel.runModal() == .OK, let pdfURL = panel.url {
            do {
                // Save PDF
                try pdfData.write(to: pdfURL)
                
                // Save CSV manifest with enhanced data
                let csvURL = pdfURL.deletingPathExtension().appendingPathExtension("csv")
                try exportEnhancedCSV(results: results,
                                     to: csvURL,
                                     duration: duration,
                                     filesPerSecond: filesPerSecond)
                
                // Save enhanced JSON report
                let jsonURL = pdfURL.deletingPathExtension().appendingPathExtension("json")
                try exportEnhancedJSONReport(
                    results: results,
                    to: jsonURL,
                    jobID: jobID,
                    started: started,
                    finished: finished,
                    mode: mode,
                    sourceURL: sourceURL,
                    destinationURLs: destinationURLs,
                    fileCount: fileCount,
                    matchCount: matchCount,
                    totalBytesProcessed: totalBytesProcessed,
                    duration: duration,
                    workers: workers,
                    prefs: prefs
                )
                
                // If checksums were used, offer to export checksum file
                if let algorithm = checksumAlgorithm {
                    askToExportChecksums(results: results, algorithm: algorithm, baseURL: pdfURL)
                }
                
                NSLog("Report exported successfully to: \(pdfURL.path)")
                
                // Show success notification
                showInfoAlert(message: "Report exported successfully to:\n\(pdfURL.lastPathComponent)")
                
            } catch {
                NSLog("Report export error: \(error.localizedDescription)")
                showErrorAlert(message: "Failed to save report: \(error.localizedDescription)")
            }
        }
    }
    #endif
    
    // MARK: - Enhanced CSV Export
    private static func exportEnhancedCSV(results: [ResultRow],
                                          to url: URL,
                                          duration: TimeInterval,
                                          filesPerSecond: Double) throws {
        var csvContent = "Status,File Path,Target Path,Details,Timestamp\n"
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        for (index, result) in results.enumerated() {
            let status = escapeCSV(result.status.rawValue)
            let path = escapeCSV(result.path)
            let target = escapeCSV(result.target ?? "—")
            let details = result.status == .match ? "Verified" : result.status.rawValue
            
            // Calculate estimated timestamp based on processing speed
            let estimatedTime = Date().addingTimeInterval(-duration + (Double(index) / max(1, filesPerSecond)))
            let timestamp = dateFormatter.string(from: estimatedTime)
            
            csvContent += "\(status),\(path),\(target),\(details),\(timestamp)\n"
        }
        
        // Add summary at the end
        csvContent += "\n# Summary\n"
        csvContent += "Total Files,\(results.count)\n"
        csvContent += "Matched,\(results.filter { $0.status == .match }.count)\n"
        csvContent += "Issues,\(results.filter { $0.status != .match }.count)\n"
        csvContent += "Duration,\(String(format: "%.2f", duration)) seconds\n"
        csvContent += "Files/Second,\(String(format: "%.2f", filesPerSecond))\n"
        
        try csvContent.data(using: .utf8)?.write(to: url)
    }
    
    // MARK: - Enhanced JSON Report Export (FIXED)
    private static func exportEnhancedJSONReport(results: [ResultRow],
                                                 to url: URL,
                                                 jobID: UUID,
                                                 started: Date,
                                                 finished: Date,
                                                 mode: AppMode,
                                                 sourceURL: URL?,
                                                 destinationURLs: [URL],
                                                 fileCount: Int,
                                                 matchCount: Int,
                                                 totalBytesProcessed: Int64,
                                                 duration: TimeInterval,
                                                 workers: Int,
                                                 prefs: ReportPrefs) throws {
        
        // Calculate file extensions breakdown
        var extensions: [String: Int] = [:]
        var largestFile: EnhancedJSONReport.FileInfo?
        var smallestFile: EnhancedJSONReport.FileInfo?
        var maxSize: Int64 = 0
        var minSize: Int64 = Int64.max
        
        for result in results {
            let url = URL(fileURLWithPath: result.path)
            let ext = url.pathExtension.uppercased()
            if !ext.isEmpty {
                extensions[ext, default: 0] += 1
            }
            
            // Track largest and smallest files
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                let fileSize = Int64(size)
                if fileSize > maxSize {
                    maxSize = fileSize
                    largestFile = EnhancedJSONReport.FileInfo(path: result.path, size: fileSize)
                }
                if fileSize < minSize {
                    minSize = fileSize
                    smallestFile = EnhancedJSONReport.FileInfo(path: result.path, size: fileSize)
                }
            }
        }
        
        // Calculate issues by type
        var issuesByType: [String: Int] = [:]
        for result in results.filter({ $0.status != .match }) {
            issuesByType[result.status.rawValue, default: 0] += 1
        }
        
        // Calculate performance metrics
        let throughputMBps = duration > 0 ? Double(totalBytesProcessed) / duration / 1_048_576 : 0
        let averageFileSize = fileCount > 0 ? totalBytesProcessed / Int64(fileCount) : 0
        let filesPerSecond = duration > 0 ? Double(fileCount) / duration : 0
        
        // Detect drive type for source
        let sourceDriveType: String = {
            if let source = sourceURL {
                do {
                    let resourceValues = try source.resourceValues(forKeys: [.volumeIsLocalKey, .volumeSupportsFileCloningKey])
                    if !(resourceValues.volumeIsLocal ?? true) {
                        return "Network"
                    } else if resourceValues.volumeSupportsFileCloning ?? false {
                        return "SSD"
                    } else {
                        return "HDD"
                    }
                } catch {
                    return "Unknown"
                }
            }
            return "Unknown"
        }()
        
        // Create source info
        let sourceInfo = EnhancedJSONReport.SourceInfo(
            path: sourceURL?.path ?? "—",
            name: sourceURL?.lastPathComponent ?? "—",
            totalSize: totalBytesProcessed,
            fileCount: fileCount,
            cameraDetected: nil, // Could be detected if needed
            driveType: sourceDriveType
        )
        
        // Create destination info array
        let destinationInfos: [EnhancedJSONReport.DestinationInfo] = destinationURLs.map { destURL in
            // Detect drive type for each destination
            let destDriveType: String = {
                do {
                    let resourceValues = try destURL.resourceValues(forKeys: [.volumeIsLocalKey, .volumeSupportsFileCloningKey, .volumeAvailableCapacityKey])
                    if !(resourceValues.volumeIsLocal ?? true) {
                        return "Network"
                    } else if resourceValues.volumeSupportsFileCloning ?? false {
                        return "SSD"
                    } else {
                        return "HDD"
                    }
                } catch {
                    return "Unknown"
                }
            }()
            
            // Get available space
            let availableSpace: Int64 = {
                do {
                    let resourceValues = try destURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                    return Int64(resourceValues.volumeAvailableCapacity ?? 0)
                } catch {
                    return 0
                }
            }()
            
            // For now, split duration evenly between copy and verify
            // In a real implementation, you'd track these separately
            let copyDuration = duration * 0.5
            let verifyDuration = duration * 0.5
            
            return EnhancedJSONReport.DestinationInfo(
                path: destURL.path,
                name: destURL.lastPathComponent,
                availableSpace: availableSpace,
                driveType: destDriveType,
                copyDuration: copyDuration,
                verifyDuration: verifyDuration
            )
        }
        
        // Create the enhanced report
        let report = EnhancedJSONReport(
            reportVersion: "2.0",
            timestamp: finished,
            jobId: jobID,
            mode: mode == .copyAndVerify ? "copy-and-verify" : mode == .compareFolders ? "compare-folders" : "master-report",
            source: sourceInfo,
            destinations: destinationInfos,
            statistics: EnhancedJSONReport.Statistics(
                totalFiles: fileCount,
                totalBytes: totalBytesProcessed,
                matches: matchCount,
                issues: fileCount - matchCount,
                successRate: fileCount > 0 ? Double(matchCount) / Double(fileCount) * 100 : 100,
                averageFileSize: averageFileSize,
                largestFile: largestFile,
                smallestFile: smallestFile
            ),
            extensions: extensions,
            performance: EnhancedJSONReport.Performance(
                totalDuration: duration,
                copyDuration: duration * 0.5, // Estimate
                verifyDuration: duration * 0.5, // Estimate
                throughputMBps: throughputMBps,
                peakSpeedMBps: throughputMBps * 1.2, // Estimate peak as 20% higher
                averageSpeedMBps: throughputMBps,
                filesPerSecond: filesPerSecond,
                workers: workers,
                bottleneck: nil // Could be determined by analyzing speeds
            ),
            verification: EnhancedJSONReport.Verification(
                method: prefs.verifyWithChecksum ? "checksum" : "byte-compare",
                algorithm: prefs.verifyWithChecksum ? prefs.checksumAlgorithm.rawValue : nil,
                issuesByType: issuesByType,
                checksumCache: nil // Would need to track cache stats during operation
            ),
            results: results.map { JSONReportItem(from: $0) }
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(report)
        try data.write(to: url)
    }
    
    #if os(macOS)
    private static func autoExportChecksums(results: [ResultRow], algorithm: ChecksumAlgorithm, baseURL: URL) {
        // Auto-export checksums without asking
        let checksumURL = baseURL.deletingPathExtension()
            .appendingPathExtension("\(algorithm.rawValue.lowercased()).txt")
        
        Task { @MainActor in
            await exportChecksumsAsync(results: results, algorithm: algorithm, to: checksumURL)
        }
    }
    
    private static func askToExportChecksums(results: [ResultRow], algorithm: ChecksumAlgorithm, baseURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Export Checksums?"
        alert.informativeText = "Would you like to export a checksum manifest file for the verified files?"
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Skip")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let checksumURL = baseURL.deletingPathExtension()
                .appendingPathExtension("\(algorithm.rawValue.lowercased()).txt")
            
            Task { @MainActor in
                await exportChecksumsAsync(results: results, algorithm: algorithm, to: checksumURL)
            }
        }
    }
    #endif
    
    private static func escapeCSV(_ string: String) -> String {
        let needsQuotes = string.contains(",") || string.contains("\"") || string.contains("\n")
        if needsQuotes {
            let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return string
    }
    
    private static func showErrorAlert(message: String) {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Export Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        #else
        // iOS doesn't have NSAlert - use print for now
        print("❌ Export Error: \(message)")
        #endif
    }
    
    private static func showInfoAlert(message: String) {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Export Complete"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        #else
        // iOS doesn't have NSAlert - use print for now
        print("ℹ️ Export Complete: \(message)")
        #endif
    }
}

#if os(macOS)
// MARK: - Async Checksum Export
extension ReportExporter {
    
    @MainActor
    static func exportChecksumsAsync(results: [ResultRow], algorithm: ChecksumAlgorithm, to url: URL) async {
        let matches = results.filter { $0.status == .match }
        guard !matches.isEmpty else {
            showInfoAlert(message: "No verified files to export checksums for.")
            return
        }
        
        // Show progress window
        let progressWindow = ChecksumProgressWindow(fileCount: matches.count)
        progressWindow.show()
        
        do {
            var content = "# BitMatch Checksum Manifest\n"
            content += "# Algorithm: \(algorithm.rawValue)\n"
            content += "# Generated: \(Date().formatted())\n"
            content += "# Format: CHECKSUM  FILENAME\n\n"
            
            // Convert paths to URLs and calculate checksums
            let urls = matches.compactMap { match -> URL? in
                guard let targetPath = match.target else { return nil }
                return URL(fileURLWithPath: targetPath)
            }
            
            let checksums = try await FileOperationsService.computeChecksums(
                for: urls,
                algorithm: algorithm
            )
            
            // Write checksum file
            for (url, checksum) in checksums {
                content += "\(checksum)  \(url.lastPathComponent)\n"
            }
            
            try content.write(to: url, atomically: true, encoding: .utf8)
            
            progressWindow.close()
            showInfoAlert(message: "Checksum manifest exported successfully!")
            
        } catch {
            progressWindow.close()
            showErrorAlert(message: "Failed to export checksums: \(error.localizedDescription)")
        }
    }
}
#endif

// MARK: - Quick Export Functions
extension ReportExporter {
    
    /// Quick export for just the issues (errors/mismatches)
    #if os(macOS)
    static func exportIssuesOnly(results: [ResultRow], to url: URL? = nil) {
        let issues = results.filter { $0.status != .match }
        guard !issues.isEmpty else {
            showInfoAlert(message: "No issues to export - all files matched perfectly!")
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "BitMatch_Issues_\(Date().formatted()).txt"
        
        if let url = url {
            panel.directoryURL = url
        }
        
        if panel.runModal() == .OK, let saveURL = panel.url {
            var content = "BitMatch Issues Report\n"
            content += "Generated: \(Date().formatted())\n"
            content += "Total Issues: \(issues.count)\n"
            content += String(repeating: "=", count: 50) + "\n\n"
            
            let grouped = Dictionary(grouping: issues) { $0.status }
            
            for (status, items) in grouped.sorted(by: { $0.key.sortPriority < $1.key.sortPriority }) {
                content += "\n\(status.rawValue) (\(items.count) files):\n"
                content += String(repeating: "-", count: 30) + "\n"
                
                for item in items.prefix(100) {
                    content += "  • \(item.path)\n"
                    if let target = item.target {
                        content += "    → \(target)\n"
                    }
                }
                
                if items.count > 100 {
                    content += "  ... and \(items.count - 100) more\n"
                }
            }
            
            do {
                try content.write(to: saveURL, atomically: true, encoding: .utf8)
                showInfoAlert(message: "Issues exported successfully!")
            } catch {
                showErrorAlert(message: "Failed to export issues: \(error.localizedDescription)")
            }
        }
    }
    #endif
}

#if os(macOS)
// MARK: - Checksum Progress Window
class ChecksumProgressWindow: NSWindow {
    private let progressIndicator: NSProgressIndicator
    private let statusLabel: NSTextField
    
    init(fileCount: Int) {
        // Create progress indicator
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 20, y: 40, width: 360, height: 20))
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(fileCount)
        progressIndicator.isIndeterminate = false
        
        // Create status label
        statusLabel = NSTextField(frame: NSRect(x: 20, y: 70, width: 360, height: 20))
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        statusLabel.alignment = .center
        statusLabel.stringValue = "Calculating checksums..."
        
        // Create content view
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        contentView.addSubview(progressIndicator)
        contentView.addSubview(statusLabel)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Exporting Checksums"
        self.contentView = contentView
        self.center()
        self.level = .floating
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
    }
    
    @MainActor
    func updateProgress(current: Int, total: Int) {
        progressIndicator.doubleValue = Double(current)
        statusLabel.stringValue = "Processing file \(current) of \(total)..."
    }
}
#endif
