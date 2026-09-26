// EvidenceReader.swift - Finds and reads BitMatch JSON reports.
import Foundation

/// Finds the JSON reports `EvidenceWriter` writes and decodes the fields the
/// Master Report needs. Mac and iPad/iPhone share this one rule for which
/// files count, how large they may be, which day they belong to, and what
/// "verified" means. The app's `ReportScanner` turns each into a card.
enum EvidenceReader {
    /// Reports larger than this are skipped rather than read into memory.
    /// A JSON report lists every file, so this allows roughly 150,000 files.
    static let maxReportBytes = 64 * 1024 * 1024

    /// A report from the chosen day that was found but not listed, so the
    /// Master Report can say so instead of leaving it only in the log.
    struct SkippedReport: Equatable, Identifiable, Sendable {
        enum Reason: Equatable, Sendable {
            case tooLarge
            case unreadable
        }
        let url: URL
        /// The path under the scanned folder, e.g. `Backup/Reports/BitMatch_Report_….json`.
        /// Exporter filenames repeat across backups, so the folder is part of the name.
        let displayName: String
        let reason: Reason
        var id: URL { url }
    }

    /// A report that was found and decoded.
    struct FoundReport: Sendable {
        let url: URL
        let snapshot: Snapshot
    }

    struct ScanResult: Sendable {
        let reports: [FoundReport]
        let skipped: [SkippedReport]
    }

    /// Scans `root` recursively for reports last written on the same calendar
    /// day as `day`. Starts security-scoped access around the scan, which iOS
    /// needs for a folder from the document picker and which is harmless
    /// elsewhere. Stops early, returning what it found so far, when the task
    /// is cancelled. `maxBytes` exists for tests.
    static func scanReports(at root: URL, day: Date = Date(), calendar: Calendar = .current,
                            maxBytes: Int = maxReportBytes) async -> ScanResult {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        SharedLogger.info("Starting report scan at: \(root.path)", category: .transfer)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            SharedLogger.error("Failed to create enumerator for: \(root.path)", category: .transfer)
            return ScanResult(reports: [], skipped: [])
        }

        var reports: [FoundReport] = []
        var skipped: [SkippedReport] = []
        func skip(_ url: URL, _ reason: SkippedReport.Reason) {
            skipped.append(SkippedReport(url: url, displayName: displayName(of: url, under: root), reason: reason))
        }
        var filesChecked = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            filesChecked += 1
            if filesChecked % 500 == 0 { await Task.yield() }

            guard isReportFilename(fileURL.lastPathComponent) else { continue }
            do {
                let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let modified = values.contentModificationDate,
                      calendar.isDate(modified, inSameDayAs: day) else { continue }
                let size = values.fileSize ?? 0
                guard size <= maxBytes else {
                    SharedLogger.warning("Skipping oversized report \(fileURL.path) (\(size) bytes)", category: .transfer)
                    skip(fileURL, .tooLarge)
                    continue
                }
                let data = try Data(contentsOf: fileURL)
                if let snapshot = snapshot(reportData: data, reportURL: fileURL) {
                    reports.append(FoundReport(url: fileURL, snapshot: snapshot))
                } else if isBitMatchNamed(fileURL.lastPathComponent) {
                    // A file BitMatch named that does not parse is a damaged
                    // report. Other apps' `*_report.json` files are ignored.
                    skip(fileURL, .unreadable)
                }
            } catch {
                SharedLogger.error("Error reading report at \(fileURL.path): \(error)", category: .transfer)
                skip(fileURL, .unreadable)
            }
        }

        SharedLogger.info("Report scan finished: \(filesChecked) files checked, \(reports.count) reports found, \(skipped.count) skipped", category: .transfer)
        return ScanResult(
            reports: reports,
            skipped: skipped.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        )
    }

    /// The path of `url` under `root`, or its filename when it is not under it.
    static func displayName(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }

    // MARK: - Rules

    /// One filename rule for every platform. It covers what the exporter
    /// writes (`BitMatch_Report_<date>.json`, and `-2` etc. when that exists),
    /// plus the older names each platform used to look for.
    static func isReportFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".json") else { return false }
        return lower == "bitmatchreport.json"
            || lower == "bitmatch_report.json"
            || lower.hasPrefix("bitmatch_report_")
            || lower.hasSuffix("_report.json")
    }

    /// Names only BitMatch writes, as opposed to the generic `*_report.json`
    /// that `isReportFilename` also accepts for older reports.
    static func isBitMatchNamed(_ name: String) -> Bool {
        name.lowercased().hasPrefix("bitmatch")
    }

    /// Reads the verification mode the report recorded. `nil` means the report
    /// does not say, and such a report is never treated as verified.
    static func verificationMode(method: String?, algorithm: String?) -> VerificationMode? {
        guard let method else { return nil }
        switch method.lowercased() {
        case "size-only", "quick": return .quick
        case "checksum":
            return algorithm?.lowercased().contains("md5") == true ? .thorough : .standard
        case "standard": return .standard
        case "thorough": return .thorough
        case "checksum-and-byte-compare", "paranoid",
             "byte-compare", "byte-to-byte", "byte_compare":
            return .paranoid
        default: return nil
        }
    }

    /// Verified means every file matched, at least one file was checked, and
    /// the report says contents were compared. A Quick (size-only) copy or a
    /// report with no recorded method is never verified (promise 2).
    static func isVerified(matches: Int, issues: Int, mode: VerificationMode?) -> Bool {
        guard let mode, mode != .quick else { return false }
        return issues == 0 && matches > 0
    }

    // MARK: - Parsing

    /// The fields the Master Report needs. Decoding only these lets older
    /// reports that lack newer fields still be found. A missing `verification`
    /// block reads as "not verified", not as a failure to parse.
    struct Snapshot: Decodable, Sendable {
        let timestamp: Date
        let source: Source
        let destinations: [Destination]
        let statistics: Statistics
        let performance: Performance
        let verification: Verification?

        struct Source: Decodable {
            let path: String
            let name: String?
            let totalSize: Int64
            let fileCount: Int
            let cameraDetected: String?
        }
        struct Destination: Decodable { let path: String }
        struct Statistics: Decodable {
            let matches: Int
            let issues: Int
        }
        struct Performance: Decodable { let totalDuration: TimeInterval }
        struct Verification: Decodable {
            let method: String
            let algorithm: String?
        }
    }

    /// Returns nil for JSON that is not a BitMatch report.
    static func snapshot(reportData: Data, reportURL: URL) -> Snapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let report = try? decoder.decode(Snapshot.self, from: reportData) else {
            SharedLogger.warning("Not a readable BitMatch report: \(reportURL.path)", category: .transfer)
            return nil
        }
        return report
    }
}
