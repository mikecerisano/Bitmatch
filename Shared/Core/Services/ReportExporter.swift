// Core/Services/ReportExporter.swift - Enhanced
import Foundation

// MARK: - Export Outcome

/// Thrown when the requested automatic report cannot be saved. Carried into the
/// completion message, the journal record, and the queue decision so verified
/// media is never confused with a failed requested report.
enum ReportExportError: LocalizedError {
    case noSaveLocation
    case missingChecksum(String)
    var errorDescription: String? {
        switch self {
        case .noSaveLocation: "Cannot find a valid directory to save reports"
        case .missingChecksum(let path): "No recorded checksum for \(path)."
        }
    }
}

// MARK: - Enhanced JSON Report Structures
struct EnhancedJSONReport: Codable {
    // Version 3.0 adds the optional photographyJob object. When it is nil,
    // every pre-existing report field retains its 2.0 meaning.
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
    let photographyJob: PhotographerReportPayload?
    var notes: String? = nil
    
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
        /// Not measured per backup; nil rather than a guess (Promise 3).
        let copyDuration: TimeInterval?
        let verifyDuration: TimeInterval?
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
        /// Copy, verify and peak speed are not measured separately; nil
        /// rather than a guess (Promise 3).
        let copyDuration: TimeInterval?
        let verifyDuration: TimeInterval?
        let throughputMBps: Double
        let peakSpeedMBps: Double?
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
    let checksum: String?
    let byteCount: Int64?

    init(from row: ResultRow) {
        self.path = row.path
        self.target = row.destinationPath ?? row.destination
        self.status = row.status.isEmpty ? "Unknown" : row.status
        self.fileExtension = URL(fileURLWithPath: row.path).pathExtension.uppercased()
        self.checksum = row.checksum
        self.byteCount = row.size
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
    
    /// `BitMatch_Report_<finish time>.<ext>`. The PDF, CSV, JSON and checksum
    /// files share this name; `ReportScanner` looks for the JSON one.
    static func reportFileName(finished: Date, pathExtension: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime
        let dateString = formatter.string(from: finished).replacingOccurrences(of: ":", with: "-")
        return "BitMatch_Report_\(dateString).\(pathExtension)"
    }

    static func normalizedNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func verificationDescription(for prefs: ReportPrefs) -> (method: String, label: String, algorithm: String?, primaryAlgorithm: ChecksumAlgorithm?) {
        switch prefs.verificationMode {
        case .quick:
            return ("size-only", "Size check only — contents not checksum verified", nil, nil)
        case .standard:
            return ("checksum", "SHA-256 checksum", "SHA-256", .sha256)
        case .thorough:
            return ("checksum", "SHA-256 and MD5 checksums", "SHA-256, MD5", .sha256)
        case .paranoid:
            return ("checksum-and-byte-compare", "SHA-256 checksum and byte comparison", "SHA-256", .sha256)
        case nil:
            return prefs.verifyWithChecksum
                ? ("checksum", "\(prefs.checksumAlgorithm.rawValue) Checksum", prefs.checksumAlgorithm.rawValue, prefs.checksumAlgorithm)
                : ("byte-compare", "Byte-to-Byte Comparison", nil, nil)
        }
    }

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
                      totalBytesProcessed: Int64,
                      generateFullReport: Bool = true,
                      photographerContext: PhotographerReportContext? = nil) async throws {
        
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let verification = verificationDescription(for: prefs)
        let method = verification.label
        
        let destinationPaths = destinationURLs.map { $0.path }
        let issues = results.filter { !isMatchStatus($0.status) }
        
        // Calculate performance metrics
        let duration = finished.timeIntervalSince(started)
        let averageSpeed = duration > 0 ? Double(totalBytesProcessed) / duration / 1_048_576 : 0 // MB/s
        let filesPerSecond = duration > 0 ? Double(fileCount) / duration : 0
        let photographerPayload = photographerContext.flatMap {
            try? PhotographerReportPayload.make(context: $0, results: results, finishedAt: finished)
        }
        
        let summary = ReportSummary(
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
            client: prefs.clientName,
            production: prefs.production,
            company: prefs.company,
            verificationMethod: method,
            totalBytesProcessed: totalBytesProcessed,
            averageSpeed: averageSpeed,
            clientLogoData: nil,
            companyLogoData: nil,
            photographyJob: photographerPayload,
            notes: normalizedNotes(prefs.notes)
        )
        
        let shouldGenerateFullReport = generateFullReport && prefs.makeReport

        // Generate PDF on main thread (required for SwiftUI views). Every
        // platform renders the same `ReportView` through `ReportPDFRenderer`
        // (Promise 5, "one app everywhere").
        let pdfData: Data? = shouldGenerateFullReport ? await MainActor.run {
            ReportPDFRenderer.renderPDF(summary: summary, results: results)
        } : nil

        try Task.checkCancellation()
        // Auto-save to reports folder
        try await autoSaveReports(mode: mode,
                             destinationURLs: destinationURLs,
                       pdfData: pdfData,
                       results: results,
                       finished: finished,
                       checksumAlgorithm: verification.primaryAlgorithm,
                       jobID: jobID,
                       started: started,
                       duration: duration,
                       sourceURL: sourceURL,
                       fileCount: fileCount,
                       matchCount: matchCount,
                       totalBytesProcessed: totalBytesProcessed,
                       workers: workers,
                       filesPerSecond: filesPerSecond,
                       prefs: prefs,
                       generateFullReport: shouldGenerateFullReport,
                       photographerContext: photographerContext)
    }
    
    private static func autoSaveReports(mode: AppMode,
                                        destinationURLs: [URL],
                                        pdfData: Data?,
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
                                        prefs: ReportPrefs,
                                        generateFullReport: Bool,
                                        photographerContext: PhotographerReportContext?) async throws {
        
        let fileName = reportFileName(finished: finished, pathExtension: "pdf")
        
        // Determine save location - auto-save to Reports folder
        let saveDirectory: URL
        if mode == .copyAndVerify, let firstDestination = destinationURLs.first {
            // Save to Reports folder inside first destination
            saveDirectory = firstDestination.appendingPathComponent("Reports", isDirectory: true)
        } else {
            // Fallback to Desktop/Reports or Documents/Reports
            guard let fallbackDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                    ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                SharedLogger.error("No valid directory found for saving reports", category: .transfer)
                throw ReportExportError.noSaveLocation
            }
            saveDirectory = fallbackDir.appendingPathComponent("Reports", isDirectory: true)
        }

        // Create reports directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        } catch {
            SharedLogger.error("Failed to create reports directory: \(error.localizedDescription)", category: .transfer)
            throw error
        }
        
        let pdfURL = saveDirectory.appendingPathComponent(fileName).nonConflictingSibling()
        
        do {
            if generateFullReport, let pdfData {
                // Save PDF
                try pdfData.write(to: pdfURL)
            }
            
            try Task.checkCancellation()
            // Save CSV manifest with enhanced data
            let csvURL = pdfURL.deletingPathExtension().appendingPathExtension("csv").nonConflictingSibling()
            try exportEnhancedCSV(results: results,
                                 to: csvURL,
                                 started: started,
                                 duration: duration,
                                 filesPerSecond: filesPerSecond,
                                 photographerContext: photographerContext,
                                 prefs: prefs)
            
            try Task.checkCancellation()
            // Save enhanced JSON report
            let jsonURL = pdfURL.deletingPathExtension().appendingPathExtension("json").nonConflictingSibling()
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
                prefs: prefs,
                photographerContext: photographerContext
            )
            
            // If checksums were used, auto-export checksum file (no dialog)
            if generateFullReport, let algorithm = checksumAlgorithm {
                let checksumURL = pdfURL.deletingPathExtension()
                    .appendingPathExtension("\(algorithm.rawValue.lowercased()).txt")
                    .nonConflictingSibling()
                try writeRecordedChecksumManifest(results: results, algorithm: algorithm, to: checksumURL)
            }
            
            SharedLogger.info("Report auto-saved successfully to: \(pdfURL.path)")

            // No need for success dialog since this is auto-save

        } catch {
            SharedLogger.info("Report export error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Enhanced CSV Export
    private static func exportEnhancedCSV(results: [ResultRow],
                                          to url: URL,
                                          started: Date,
                                          duration: TimeInterval,
                                          filesPerSecond: Double,
                                          photographerContext: PhotographerReportContext? = nil,
                                          prefs: ReportPrefs? = nil) throws {
        let csvContent = try makeEnhancedCSV(
            results: results,
            started: started,
            duration: duration,
            filesPerSecond: filesPerSecond,
            photographerContext: photographerContext,
            prefs: prefs
        )
        try csvContent.data(using: .utf8)?.write(to: url)
    }

    static func makeEnhancedCSV(
        results: [ResultRow],
        started: Date,
        duration: TimeInterval,
        filesPerSecond: Double,
        photographerContext: PhotographerReportContext?,
        prefs: ReportPrefs? = nil
    ) throws -> String {
        let payload = try photographerContext.map {
            try PhotographerReportPayload.make(context: $0, results: results)
        }
        var csvContent = csvRow([
            "Status", "File Path", "Target Path", "Job", "Photographer", "Camera", "Card", "Package Path", "Details", "Timestamp", "Bytes", "Checksum"
        ])
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        for result in results {
            let status = result.status
            let path = result.path
            let target = result.destinationPath ?? result.destination ?? "—"
            let job = payload?.jobName ?? ""
            let photographer = payload?.card.provenance.photographerName ?? ""
            let camera = payload?.card.provenance.cameraName ?? ""
            let card = payload.map { String(format: "Card %03d", $0.card.provenance.cardNumber) } ?? ""
            let packagePath = payload?.card.renderedRelativePath ?? ""
            let verified = isMatchStatus(result.status) && result.checksum?.isEmpty == false && prefs?.verificationMode != .quick
            let details = verified ? "Verified" : result.status
            
            // Per-file times are not measured; the column stays for existing
            // spreadsheets but is empty rather than interpolated (Promise 3).
            // The run's measured start and finish are in the summary.
            let timestamp = ""

            csvContent += csvRow([
                status, path, target, job, photographer, camera, card, packagePath, details, timestamp,
                String(result.size), result.checksum ?? ""
            ])
        }
        
        // Add summary at the end
        csvContent += "\n# Summary\n"
        csvContent += csvRow(["Total Files", String(results.count)])
        csvContent += csvRow(["Started", dateFormatter.string(from: started)])
        csvContent += csvRow(["Finished", dateFormatter.string(from: started.addingTimeInterval(duration))])
        // Verified and copied-but-unverified are counted apart (Promise 2):
        // a Quick copy is not a match.
        csvContent += csvRow(["Verified", String(results.filter { TransferOutcomePresentation.isVerified($0) }.count)])
        csvContent += csvRow(["Copied, not verified", String(results.filter { isMatchStatus($0.status) && !TransferOutcomePresentation.isVerified($0) }.count)])
        csvContent += csvRow(["Issues", String(results.filter { !isMatchStatus($0.status) }.count)])
        csvContent += csvRow(["Duration", "\(String(format: "%.2f", duration)) seconds"])
        csvContent += csvRow(["Files/Second", String(format: "%.2f", filesPerSecond)])
        if let payload {
            csvContent += csvRow(["Locally Safe", payload.isLocallySafe ? "Yes" : "No"])
            csvContent += csvRow(["Fully Backed Up", payload.fullyBackedUpAt?.ISO8601Format() ?? "—"])
            for evidence in payload.remoteBackupEvidence {
                csvContent += csvRow(["Off-site Backup", evidence.status, evidence.remotePath ?? "—", evidence.errorSummary ?? ""])
            }
        }
        
        if let prefs {
            csvContent += csvRow(["Verification", verificationDescription(for: prefs).label])
            if let notes = normalizedNotes(prefs.notes) {
                csvContent += csvRow(["Notes", notes])
            }
        }
        return csvContent
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
                                                 prefs: ReportPrefs,
                                                 photographerContext: PhotographerReportContext? = nil) throws {
        let report = try makeEnhancedJSONReport(
            results: results,
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
            prefs: prefs,
            photographerContext: photographerContext
        )
        try encodeEnhancedJSONReport(report).write(to: url)
    }

    /// The bytes written for a JSON report. `ReportScanner` reads these back.
    static func encodeEnhancedJSONReport(_ report: EnhancedJSONReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    static func makeEnhancedJSONReport(
        results: [ResultRow],
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
        prefs: ReportPrefs,
        photographerContext: PhotographerReportContext?
    ) throws -> EnhancedJSONReport {
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
        for result in results.filter({ !isMatchStatus($0.status) }) {
            let key = normalizedStatus(result.status)
            issuesByType[key, default: 0] += 1
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
            
            return EnhancedJSONReport.DestinationInfo(
                path: destURL.path,
                name: destURL.lastPathComponent,
                availableSpace: availableSpace,
                driveType: destDriveType,
                copyDuration: nil,
                verifyDuration: nil
            )
        }
        
        // Create the enhanced report
        return EnhancedJSONReport(
            reportVersion: "3.0",
            timestamp: finished,
            jobId: jobID,
            mode: mode == .copyAndVerify ? "copy-and-verify" : mode == .compareFolders ? "compare-folders" : "master-report",
            source: sourceInfo,
            destinations: destinationInfos,
            statistics: EnhancedJSONReport.Statistics(
                totalFiles: fileCount,
                totalBytes: totalBytesProcessed,
                matches: matchCount,
                // Failed rows only: a copied-but-unverified file is neither a
                // match nor an issue.
                issues: results.filter { !isMatchStatus($0.status) }.count,
                successRate: fileCount > 0 ? Double(matchCount) / Double(fileCount) * 100 : 100,
                averageFileSize: averageFileSize,
                largestFile: largestFile,
                smallestFile: smallestFile
            ),
            extensions: extensions,
            performance: EnhancedJSONReport.Performance(
                totalDuration: duration,
                copyDuration: nil,
                verifyDuration: nil,
                throughputMBps: throughputMBps,
                peakSpeedMBps: nil,
                averageSpeedMBps: throughputMBps,
                filesPerSecond: filesPerSecond,
                workers: workers,
                bottleneck: nil // Could be determined by analyzing speeds
            ),
            verification: EnhancedJSONReport.Verification(
                method: verificationDescription(for: prefs).method,
                algorithm: verificationDescription(for: prefs).algorithm,
                issuesByType: issuesByType,
                checksumCache: nil // Would need to track cache stats during operation
            ),
            results: results.map { JSONReportItem(from: $0) },
            photographyJob: try photographerContext.map {
                try PhotographerReportPayload.make(context: $0, results: results, finishedAt: finished)
            },
            notes: normalizedNotes(prefs.notes)
        )
    }
    
    /// Automatic reports use the checksums retained by verification. Re-reading
    /// files later would replace the evidence and outlive the transfer's access lease.
    static func writeRecordedChecksumManifest(results: [ResultRow], algorithm: ChecksumAlgorithm, to url: URL) throws {
        var content = "# BitMatch Checksum Manifest\n# Algorithm: \(algorithm.rawValue)\n# Format: CHECKSUM  FILENAME\n\n"
        for row in results where row.isSuccessStatus {
            try Task.checkCancellation()
            guard let checksum = row.checksum, !checksum.isEmpty else {
                throw ReportExportError.missingChecksum(row.path)
            }
            let path = row.destinationPath ?? row.path
            // GNU checksum escaping preserves filenames containing backslashes or newlines.
            let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
            content += (escaped == path ? "" : "\\") + checksum + "  " + escaped + "\n"
        }
        try Task.checkCancellation()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func csvRow(_ values: [String]) -> String {
        values.map(escapeCSV).joined(separator: ",") + "\n"
    }

    private static func escapeCSV(_ string: String) -> String {
        let neutralized = neutralizeCSVFormula(string)
        let needsQuotes = neutralized.contains(",")
            || neutralized.contains("\"")
            || neutralized.contains("\n")
            || neutralized.contains("\r")
        if needsQuotes {
            let escaped = neutralized.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return neutralized
    }

    private static func neutralizeCSVFormula(_ string: String) -> String {
        guard let firstContentScalar = string.unicodeScalars.first(where: {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }), ["=", "+", "-", "@"].contains(String(firstContentScalar)) else {
            return string
        }
        return "'\(string)"
    }
    
    private static func isMatchStatus(_ status: String) -> Bool {
        ResultRow.isSuccessStatus(status)
    }
    
    private static func normalizedStatus(_ status: String) -> String {
        status.isEmpty ? "Unknown" : status
    }
}
