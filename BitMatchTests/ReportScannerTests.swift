import Foundation
import Testing
@testable import BitMatch

/// The Master Report scanner shared by Mac and iPad/iPhone (UI plan step 4.4).
/// Reports are built by `ReportExporter.makeEnhancedJSONReport`, encoded with
/// the exporter's own encoder, and written under the exporter's filename into
/// real temporary folders, so these fail if the scanner and the exporter drift.
struct ReportScannerTests {

    // MARK: - Fixtures

    private func makeTemporaryFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReportScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func reportData(mode: VerificationMode, fileCount: Int = 2, matchCount: Int = 2,
                            root: URL, finished: Date) throws -> Data {
        let rows = (0..<fileCount).map { index in
            ResultRow(path: root.appendingPathComponent("A001/CLIP\(index).MOV").path,
                      status: index < matchCount ? "✅ Verified" : "❌ Failed",
                      size: 10, checksum: "abc\(index)", destination: "Backup")
        }
        let report = try ReportExporter.makeEnhancedJSONReport(
            results: rows,
            jobID: UUID(),
            started: finished.addingTimeInterval(-60),
            finished: finished,
            mode: .copyAndVerify,
            sourceURL: root.appendingPathComponent("A001", isDirectory: true),
            destinationURLs: [root.appendingPathComponent("Backup", isDirectory: true)],
            fileCount: fileCount,
            matchCount: matchCount,
            totalBytesProcessed: Int64(fileCount * 10),
            duration: 60,
            workers: 1,
            prefs: ReportPrefs(verificationMode: mode),
            photographerContext: nil
        )
        return try ReportExporter.encodeEnhancedJSONReport(report)
    }

    /// Writes where and how the exporter does: `<backup>/Reports/BitMatch_Report_<date>.json`,
    /// with a `-2` sibling when that name is taken.
    @discardableResult
    private func writeReport(mode: VerificationMode, fileCount: Int = 2, matchCount: Int = 2,
                             root: URL, finished: Date = Date()) throws -> URL {
        let reports = root.appendingPathComponent("Backup/Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let url = reports
            .appendingPathComponent(ReportExporter.reportFileName(finished: finished, pathExtension: "json"))
            .nonConflictingSibling()
        try reportData(mode: mode, fileCount: fileCount, matchCount: matchCount, root: root, finished: finished)
            .write(to: url)
        return url
    }

    // MARK: - Filenames

    /// Plant: in `ReportScanner.isReportFilename`, delete the line
    /// `|| lower.hasPrefix("bitmatch_report_")`. (The old iOS rule,
    /// `name == "BitMatchReport.json" || name.hasSuffix("_Report.json")`, fails it too.)
    @Test func findsExporterFilenames() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let finished = Date()
        let first = try writeReport(mode: .standard, root: root, finished: finished)
        let second = try writeReport(mode: .standard, root: root, finished: finished)
        #expect(first.lastPathComponent.hasPrefix("BitMatch_Report_"))
        #expect(second.lastPathComponent != first.lastPathComponent)

        let cards = await ReportScanner.scan(at: root)
        #expect(cards.count == 2)
    }

    // MARK: - What "verified" means

    /// Positive control, so the tests below cannot pass by rejecting everything.
    /// Plant: in `ReportScanner.verificationMode(method:algorithm:)`, change
    /// `case "checksum":` to `case "checksum-legacy":`.
    @Test func standardReportIsVerified() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeReport(mode: .standard, root: root)

        let cards = await ReportScanner.scan(at: root)
        #expect(cards.count == 1)
        #expect(cards.first?.verified == true)
        #expect(cards.first?.metadata?.verificationMode == .standard)
    }

    /// A Quick copy checks sizes only; its report must not read as verified.
    /// Plant: in `ReportScanner.transferCard(from:reportURL:)`, change the
    /// `let verified = ...` line to `let verified = report.statistics.issues == 0`.
    @Test func quickModeReportIsNotVerified() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeReport(mode: .quick, root: root)

        let cards = await ReportScanner.scan(at: root)
        #expect(cards.count == 1)
        #expect(cards.first?.verified == false)
        #expect(cards.first?.metadata?.verificationMode == .quick)
    }

    /// A report whose method this build does not know is not verified.
    /// Plant: in `ReportScanner.verificationMode(method:algorithm:)`, change
    /// `default: return nil` to `default: return .standard`.
    @Test func unknownVerificationMethodIsNotVerified() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try reportData(mode: .standard, root: root, finished: Date())
        let parsed = try JSONSerialization.jsonObject(with: data)
        var object = try #require(parsed as? [String: Any])
        var verification = try #require(object["verification"] as? [String: Any])
        verification["method"] = "future-method"
        object["verification"] = verification
        let edited = try JSONSerialization.data(withJSONObject: object)

        let card = try #require(ReportScanner.transferCard(reportData: edited, reportURL: root.appendingPathComponent("r.json")))
        #expect(card.verified == false)
    }

    /// A report with failures is not verified, whatever its mode.
    /// Plant: in `ReportScanner.isVerified`, change `issues == 0 && matches > 0`
    /// to `matches > 0`.
    @Test func reportWithIssuesIsNotVerified() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeReport(mode: .paranoid, fileCount: 3, matchCount: 2, root: root)

        let cards = await ReportScanner.scan(at: root)
        #expect(cards.count == 1)
        #expect(cards.first?.verified == false)
    }

    // MARK: - Date window

    /// Only reports written on the chosen day are listed (default: today).
    /// Plant: in `ReportScanner.scan`, change
    /// `calendar.isDate(modified, inSameDayAs: day) else { continue }` to
    /// `modified <= Date() else { continue }`.
    @Test func reportFromAnotherDayIsSkipped() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let threeDaysAgo = try #require(Calendar.current.date(byAdding: .day, value: -3, to: Date()))
        let url = try writeReport(mode: .standard, root: root, finished: threeDaysAgo)
        try FileManager.default.setAttributes([.modificationDate: threeDaysAgo], ofItemAtPath: url.path)

        let today = await ReportScanner.scan(at: root)
        #expect(today.isEmpty)
        let thatDay = await ReportScanner.scan(at: root, day: threeDaysAgo)
        #expect(thatDay.count == 1)
    }
}
