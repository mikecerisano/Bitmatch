import Foundation
import BitMatchEngine

/// How the outcome screen colours its verdict. It comes from the operation
/// state and the verdict, never from a symbol name, so a cancelled transfer
/// is always `.cancelled` (neither red "failed" nor amber "review").
enum OutcomeTone: Equatable, Sendable {
    case verified
    case needsReview
    case failed
    case cancelled

    static func make(state: OperationState, verdict: CompletionVerdict) -> Self {
        if state == .cancelled { return .cancelled }
        switch verdict {
        case .success: return .verified
        case .issues: return .needsReview
        case .failed: return .failed
        }
    }
}

/// The action the outcome screen draws as its prominent button: the step
/// the user most likely takes next.
enum OutcomePrimaryAction: Equatable, Sendable {
    case newTransfer
    case retry
}

/// File results by how they ended. A row is one file on one backup.
struct OutcomeFileCounts: Equatable, Sendable {
    let verified: Int
    let copiedNotVerified: Int
    let needsAttention: Int

    var total: Int { verified + copiedNotVerified + needsAttention }

    static func make(rows: [ResultRow]) -> Self {
        var verified = 0
        var copied = 0
        var attention = 0
        for row in rows {
            if !row.isSuccessStatus {
                attention += 1
            } else if TransferOutcomePresentation.isVerified(row) {
                verified += 1
            } else {
                copied += 1
            }
        }
        return Self(verified: verified, copiedNotVerified: copied, needsAttention: attention)
    }
}

/// One backup's line on the outcome screen.
struct OutcomeDestinationLine: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let needsAttention: Bool
}

/// Everything the shared `OutcomeScreen` shows for a finished, failed or
/// cancelled transfer, on Mac, iPad and iPhone (UI plan step 4.7).
///
/// It only *presents* the verdict: `CompletionVerdict` and the state-aware
/// `CompletionVerdictPresentation.make(state:…)` decide it. Guidance, tone,
/// issue lines, counts and duration wording all live here so no view has its
/// own copy of them.
struct TransferOutcomePresentation: Equatable, Sendable {
    /// The file list shows at most this many rows; the export has them all.
    static let fileListLimit = 1_000

    let verdict: CompletionVerdictPresentation
    let tone: OutcomeTone
    /// The one sentence about the source card. Exactly one source of truth.
    let guidance: String
    /// "N files failed", errors, warnings. Empty when the
    /// transfer was cancelled or verified.
    let issueLines: [String]
    /// "Completed in …", or "Stopped after …" for a cancelled transfer.
    let durationLabel: String?
    let counts: OutcomeFileCounts
    /// Bytes of verified files, summed over every backup. Nil when
    /// nothing was verified; never the source folder size.
    let bytesVerified: Int64?
    let verificationModeLabel: String?
    let destinations: [OutcomeDestinationLine]
    let rowCount: Int
    let rowsTruncated: Bool
    let canRetry: Bool
    let canExport: Bool
    let primaryAction: OutcomePrimaryAction
    /// Decision O-1: New transfer clears the source and keeps the backups.
    let newTransferNote: String?

    var isCancelled: Bool { tone == .cancelled }

    /// Spoken when the screen appears (audit C3).
    var announcement: String { "\(verdict.title). \(verdict.detail)" }

    static func make(
        state: OperationState,
        rows: [ResultRow],
        destinations: [URL],
        hasErrors: Bool,
        hasCriticalErrors: Bool,
        errorCount: Int,
        warningCount: Int,
        duration: TimeInterval?,
        verificationMode: VerificationMode?,
        canRetry: Bool,
        canExport: Bool
    ) -> Self {
        let resolved = CompletionVerdict.resolve(
            state: state,
            rows: rows,
            hasErrors: hasErrors,
            hasCriticalErrors: hasCriticalErrors
        )
        let verdict = CompletionVerdictPresentation.make(
            state: state,
            rows: rows,
            hasErrors: hasErrors,
            hasCriticalErrors: hasCriticalErrors
        )
        let tone = OutcomeTone.make(state: state, verdict: resolved)
        let counts = OutcomeFileCounts.make(rows: rows)

        let verifiedBytes = rows.filter(Self.isVerified).reduce(into: Int64(0)) { total, row in
            let (sum, overflow) = total.addingReportingOverflow(max(0, row.size))
            total = overflow ? .max : sum
        }

        let needsRetry = tone == .failed
            || (tone == .needsReview && (counts.needsAttention > 0 || errorCount > 0))
        let backupCount = destinations.count

        return Self(
            verdict: verdict,
            tone: tone,
            guidance: verdict.sourceGuidance ?? "Review the transfer evidence before clearing source media.",
            issueLines: makeIssueLines(tone: tone, counts: counts, errorCount: errorCount, warningCount: warningCount),
            durationLabel: duration.map { makeDurationLabel(tone: tone, state: state, seconds: $0) },
            counts: counts,
            bytesVerified: counts.verified > 0 ? verifiedBytes : nil,
            verificationModeLabel: verificationMode.map { "\($0.rawValue) mode" },
            destinations: makeDestinationLines(rows: rows, destinations: destinations, cancelled: tone == .cancelled),
            rowCount: rows.count,
            rowsTruncated: rows.count > fileListLimit,
            canRetry: canRetry,
            canExport: canExport,
            primaryAction: canRetry && needsRetry ? .retry : .newTransfer,
            newTransferNote: backupCount == 0 ? nil
                : backupCount == 1 ? "Keeps the same backup. Choose the next card."
                : "Keeps the same \(backupCount) backups. Choose the next card."
        )
    }

    // MARK: - Pieces

    /// Green only for a row that positively says it was verified; the same
    /// rule as the per-row symbol (`ResultStatusPresentation`).
    static func isVerified(_ row: ResultRow) -> Bool {
        row.isVerifiedStatus
    }

    /// Plain words for a row's status (audit L7: no emoji read aloud).
    static func statusLabel(for status: String) -> String {
        guard let outcome = ResultOutcome(statusText: status) else { return status }
        switch outcome {
        case .verified: return "Verified"
        case .copiedUnverified: return "Copied, not verified"
        case .checksumMismatch: return "Checksum mismatch"
        case .failed: return "Failed"
        }
    }

    /// Audit H12: one spoken stop per file result ("name, status, size,
    /// destination") instead of four or five separate VoiceOver stops per
    /// row, with no column names to say what "80 KB" means.
    static func accessibilityLabel(for row: ResultRow) -> String {
        let name = URL(fileURLWithPath: row.path).lastPathComponent
        let status = statusLabel(for: row.status)
        let size = ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)
        guard let destination = row.destination, !destination.isEmpty else {
            return "\(name), \(status), \(size)"
        }
        return "\(name), \(status), \(size), \(destination)"
    }

    func emptyFileListText(issuesOnly: Bool) -> String {
        if rowCount == 0 {
            return isCancelled
                ? "No files were recorded before the transfer was cancelled."
                : "No files were recorded."
        }
        return issuesOnly ? "No issues found." : "No files to show."
    }

    var truncationNote: String? {
        rowsTruncated
            ? "Showing \(Self.fileListLimit.formatted()) of \(rowCount.formatted()) files. Export a report for the full record."
            : nil
    }

    private static func makeIssueLines(
        tone: OutcomeTone,
        counts: OutcomeFileCounts,
        errorCount: Int,
        warningCount: Int
    ) -> [String] {
        // A cancelled run's unfinished files are not failures, and cancelling
        // itself is logged as a warning: say neither.
        guard tone != .cancelled else { return [] }
        var lines: [String] = []
        if counts.needsAttention > 0 {
            lines.append(counts.needsAttention == 1
                ? "1 file failed"
                : "\(counts.needsAttention) files failed")
        }
        if counts.copiedNotVerified > 0 {
            lines.append(counts.copiedNotVerified == 1
                ? "1 file copied, not verified"
                : "\(counts.copiedNotVerified) files copied, not verified")
        }
        if errorCount > 0 {
            lines.append(errorCount == 1 ? "1 reported error" : "\(errorCount) reported errors")
        }
        if warningCount > 0 {
            lines.append(warningCount == 1 ? "1 warning" : "\(warningCount) warnings")
        }
        return lines
    }

    private static func makeDurationLabel(tone: OutcomeTone, state: OperationState, seconds: TimeInterval) -> String {
        let text = durationText(seconds)
        switch tone {
        case .cancelled: return "Stopped after \(text)"
        case .failed: return "Ended after \(text)"
        case .verified, .needsReview:
            if case .completed = state { return "Completed in \(text)" }
            return "Ended after \(text)"
        }
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(secs)s" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    private static func makeDestinationLines(rows: [ResultRow], destinations: [URL], cancelled: Bool) -> [OutcomeDestinationLine] {
        DestinationResultSummary.make(rows: rows, destinations: destinations).map { summary in
            guard cancelled else {
                return OutcomeDestinationLine(
                    id: summary.id,
                    title: summary.title,
                    detail: summary.detail,
                    needsAttention: summary.needsAttention
                )
            }
            let verified = summary.rows.filter(Self.isVerified).count
            let detail = summary.rows.isEmpty
                ? "Cancelled before any files were recorded"
                : "Cancelled: \(verified) of \(summary.rows.count) files verified before the stop"
            return OutcomeDestinationLine(id: summary.id, title: summary.title, detail: detail, needsAttention: true)
        }
    }
}

/// Counts for a live results list, taken from the rows themselves.
struct LiveResultsCounts: Equatable {
    let verified: Int
    let copiedNotVerified: Int
    let issues: Int

    static func make(rows: [ResultRow]) -> Self {
        var verified = 0, copied = 0, issues = 0
        for row in rows {
            if !row.isSuccessStatus {
                issues += 1
            } else if TransferOutcomePresentation.isVerified(row) {
                verified += 1
            } else {
                copied += 1
            }
        }
        return Self(verified: verified, copiedNotVerified: copied, issues: issues)
    }

    /// What the "no issues" view says: "all verified" only when every row
    /// was verified (Promise 2).
    var noIssuesMessage: String? {
        switch (verified, copiedNotVerified) {
        case (0, 0): return nil
        case (_, 0): return "All \(verified) files verified"
        case (0, _): return "\(copiedNotVerified) files copied, not verified"
        default: return "\(verified) verified, \(copiedNotVerified) copied but not verified"
        }
    }
}
