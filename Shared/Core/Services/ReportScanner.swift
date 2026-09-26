// ReportScanner.swift - Turns found reports into Master Report cards.
import Foundation
import BitMatchEngine

/// The app's side of reading reports: `EvidenceReader` finds and decodes
/// them (the same rules on every platform), and this maps each one to a
/// `TransferCard` for the Master Report. Only choosing the folder differs
/// by platform.
enum ReportScanner {
    typealias SkippedReport = EvidenceReader.SkippedReport
    typealias Snapshot = EvidenceReader.Snapshot

    struct ScanResult {
        let cards: [TransferCard]
        let skipped: [SkippedReport]
    }

    /// Cards for the reports written on the same calendar day as `day`.
    static func scan(at root: URL, day: Date = Date(), calendar: Calendar = .current) async -> [TransferCard] {
        await scanReports(at: root, day: day, calendar: calendar).cards
    }

    /// `scan`, plus the reports from that day that were skipped because they
    /// were too large or could not be read. `maxBytes` exists for tests.
    static func scanReports(at root: URL, day: Date = Date(), calendar: Calendar = .current,
                            maxBytes: Int = EvidenceReader.maxReportBytes) async -> ScanResult {
        let found = await EvidenceReader.scanReports(at: root, day: day, calendar: calendar, maxBytes: maxBytes)
        let cards = found.reports.map { transferCard(from: $0.snapshot, reportURL: $0.url) }
        return ScanResult(cards: cards.sorted { $0.timestamp > $1.timestamp }, skipped: found.skipped)
    }

    /// Returns nil for JSON that is not a BitMatch report.
    static func transferCard(reportData: Data, reportURL: URL) -> TransferCard? {
        EvidenceReader.snapshot(reportData: reportData, reportURL: reportURL)
            .map { transferCard(from: $0, reportURL: reportURL) }
    }

    static func transferCard(from report: Snapshot, reportURL: URL) -> TransferCard {
        let mode = EvidenceReader.verificationMode(method: report.verification?.method, algorithm: report.verification?.algorithm)
        let verified = EvidenceReader.isVerified(matches: report.statistics.matches, issues: report.statistics.issues, mode: mode)
        let sourceURL = URL(fileURLWithPath: report.source.path)
        let destinationURLs = report.destinations.map { URL(fileURLWithPath: $0.path) }
        let cameraName = cameraName(for: report)
        // The exporter stamps the report when the transfer finished.
        let finished = report.timestamp
        let started = finished.addingTimeInterval(-max(0, report.performance.totalDuration))

        func folder(_ url: URL) -> FolderInfo {
            FolderInfo(url: url, fileCount: report.source.fileCount, totalSize: report.source.totalSize,
                       lastModified: finished, isInternalDrive: !url.path.hasPrefix("/Volumes/"))
        }

        let cameraCard = CameraCard(
            name: cameraName,
            manufacturer: manufacturer(for: cameraName),
            model: cameraName,
            fileCount: report.source.fileCount,
            totalSize: report.source.totalSize,
            detectionConfidence: report.source.cameraDetected != nil ? 0.95 : 0.6,
            metadata: ["reportPath": reportURL.path, "reportTimestamp": finished],
            volumeURL: sourceURL,
            cameraType: cameraType(for: cameraName),
            mediaPath: sourceURL
        )
        let metadata = TransferMetadata(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            startTime: started,
            endTime: finished,
            totalFiles: report.source.fileCount,
            totalSize: report.source.totalSize,
            // An unrecorded mode is shown as Quick, the weakest claim.
            verificationMode: mode ?? .quick,
            cameraSettings: nil
        )
        let message: String
        if verified {
            message = "Verified"
        } else if report.statistics.issues > 0 {
            message = "\(report.statistics.issues) issues"
        } else {
            message = "Not verified"
        }
        return TransferCard(
            source: folder(sourceURL),
            destinations: destinationURLs.map(folder),
            cameraCard: cameraCard,
            metadata: metadata,
            progress: 1.0,
            state: .completed(OperationCompletionInfo(success: verified, message: message))
        )
    }

    /// The detected camera, else the card's folder name. The Master Report
    /// groups cards by this name.
    static func cameraName(for report: Snapshot) -> String {
        if let detected = report.source.cameraDetected?.trimmingCharacters(in: .whitespaces), !detected.isEmpty {
            return detected
        }
        if let name = report.source.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != "—" {
            return name
        }
        let last = URL(fileURLWithPath: report.source.path).lastPathComponent
        return last.isEmpty || last == "—" || last == "/" ? "Unknown Camera" : last
    }

    private static func manufacturer(for cameraName: String) -> String {
        let upper = cameraName.uppercased()
        if upper.contains("SONY") || upper.contains("FX") || upper.contains("A7") { return "Sony" }
        if upper.contains("CANON") || upper.contains("C70") || upper.contains("C100") { return "Canon" }
        if upper.contains("RED") || upper.contains("DRAGON") { return "RED" }
        if upper.contains("ARRI") || upper.contains("ALEXA") { return "ARRI" }
        if upper.contains("BLACKMAGIC") || upper.contains("URSA") { return "Blackmagic" }
        if upper.contains("DJI") { return "DJI" }
        if upper.contains("GOPRO") { return "GoPro" }
        return "Unknown"
    }

    private static func cameraType(for cameraName: String) -> CameraType {
        let upper = cameraName.uppercased()
        if upper.contains("SONY") && upper.contains("FX6") { return .sonyFX6 }
        if upper.contains("SONY") && upper.contains("FX3") { return .sonyFX3 }
        if upper.contains("SONY") && upper.contains("A7") { return .sonyA7S }
        if upper.contains("SONY") { return .sony }
        if upper.contains("CANON") && upper.contains("C70") { return .canonC70 }
        if upper.contains("CANON") { return .canon }
        if upper.contains("ARRI") || upper.contains("ALEXA") { return .arriAlexa }
        if upper.contains("RED") { return .redCamera }
        if upper.contains("BLACKMAGIC") { return .blackmagic }
        if upper.contains("GOPRO") { return .gopro }
        if upper.contains("DJI") { return .dji }
        return .generic
    }
}
