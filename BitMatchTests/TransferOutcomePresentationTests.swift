import Foundation
import Testing
@testable import BitMatch
import BitMatchEngine

/// UI plan step 4.7: the shared outcome screen's model. Mac, iPad and iPhone
/// all build it through `TransferOutcomePresentation.make`, so these pin the
/// behaviour on every platform.
struct TransferOutcomePresentationTests {
    private let backupA = URL(fileURLWithPath: "/Volumes/A/Backup", isDirectory: true)
    private let backupB = URL(fileURLWithPath: "/Volumes/B/Backup", isDirectory: true)

    private func row(_ name: String, _ outcome: ResultOutcome, size: Int64 = 100, backup: URL) -> ResultRow {
        ResultRow(
            path: "/Card/\(name)",
            status: outcome.statusText,
            size: size,
            checksum: outcome == .verified ? "abc" : nil,
            destination: backup.lastPathComponent,
            destinationPath: backup.appendingPathComponent(name).path
        )
    }

    private func make(
        state: OperationState,
        rows: [ResultRow],
        hasErrors: Bool = false,
        errorCount: Int = 0,
        warningCount: Int = 0,
        duration: TimeInterval? = 75,
        canRetry: Bool = true
    ) -> TransferOutcomePresentation {
        TransferOutcomePresentation.make(
            state: state,
            rows: rows,
            destinations: [backupA, backupB],
            hasErrors: hasErrors,
            hasCriticalErrors: false,
            errorCount: errorCount,
            warningCount: warningCount,
            duration: duration,
            verificationMode: .standard,
            canRetry: canRetry,
            canExport: true
        )
    }

    private var partialRows: [ResultRow] {
        [
            row("A001.mov", .verified, backup: backupA),
            row("A002.mov", .copiedUnverified, backup: backupA),
            row("A001.mov", .verified, backup: backupB),
        ]
    }

    private var cleanRows: [ResultRow] {
        [row("A001.mov", .verified, backup: backupA), row("A001.mov", .verified, backup: backupB)]
    }

    // MARK: Cancelled says cancelled

    // Plant: in `OutcomeTone.make`, derive the tone from the verdict symbol
    // (`presentation.symbol == "checkmark.circle.fill" ? .verified : … : .failed`),
    // as the old Mac `completionTint` did.
    @Test func cancelledToneIsCancelled() {
        let outcome = make(state: .cancelled, rows: partialRows, hasErrors: true, warningCount: 1)
        #expect(outcome.tone == .cancelled)
        #expect(outcome.verdict.title == "Transfer cancelled")
    }

    // Plant: in `makeIssueLines`, delete `guard tone != .cancelled else { return [] }`.
    @Test func cancelledHasNoIssueLines() {
        // Cancelling logs a warning and leaves unverified rows: neither is a failure.
        let outcome = make(state: .cancelled, rows: partialRows, hasErrors: true, warningCount: 1)
        #expect(outcome.issueLines.isEmpty)
    }

    // Plant: in `TransferOutcomePresentation.make`, set
    // `guidance: CompletionVerdictPresentation.make(resolved).sourceGuidance ?? ""`
    // (the verdict-only text the old iPad issue box used).
    @Test func cancelledGuidanceIsNotFailedFileGuidance() {
        let outcome = make(state: .cancelled, rows: partialRows, hasErrors: true, warningCount: 1)
        #expect(outcome.guidance == "Keep source media intact until a transfer completes.")
        #expect(!outcome.guidance.contains("failed"))
    }

    // Plant: in `TransferOutcomePresentation.make`, call
    // `makeDestinationLines(…, cancelled: false)`.
    @Test func cancelledBackupLinesSayCancelled() {
        let outcome = make(state: .cancelled, rows: partialRows)
        #expect(outcome.destinations.count == 2)
        #expect(outcome.destinations.allSatisfy { $0.detail.hasPrefix("Cancelled") })
        #expect(outcome.destinations.first?.detail == "Cancelled: 1 of 2 file results verified before the stop")
    }

    // Plant: in `makeDurationLabel`, return `"Completed in \(text)"` for every tone.
    @Test func durationSaysStoppedWhenCancelled() {
        #expect(make(state: .cancelled, rows: partialRows).durationLabel == "Stopped after 1m 15s")
        let done = make(state: .completed(OperationCompletionInfo(success: true, message: "Operation completed successfully")), rows: cleanRows)
        #expect(done.durationLabel == "Completed in 1m 15s")
    }

    // Plant: in `emptyFileListText`, drop the `isCancelled` branch.
    @Test func emptyCancelledListSaysCancelled() {
        let outcome = make(state: .cancelled, rows: [])
        #expect(outcome.emptyFileListText(issuesOnly: false).contains("cancelled"))
    }

    // MARK: Evidence

    // Plant: in `TransferOutcomePresentation.make`, sum every row's size
    // (`rows.reduce(0) { $0 + $1.size }`) instead of only verified rows.
    @Test func bytesAreVerifiedNotEverything() {
        let rows = [
            row("A001.mov", .verified, size: 100, backup: backupA),
            row("A001.mov", .verified, size: 200, backup: backupB),
            row("A002.mov", .failed, size: 50, backup: backupA),
            row("A003.mov", .copiedUnverified, size: 25, backup: backupB),
        ]
        let outcome = make(state: .completed(OperationCompletionInfo(success: false, message: "Operation completed with 1 issue")), rows: rows)
        #expect(outcome.bytesVerified == 300)
        #expect(outcome.counts == OutcomeFileCounts(verified: 2, copiedNotVerified: 1, needsAttention: 1))
    }

    // Plant: in `OutcomeFileCounts.make`, count every success row as verified.
    @Test func quickCopiesAreNotCountedVerified() {
        let rows = [row("A001.mov", .copiedUnverified, backup: backupA)]
        let outcome = make(state: .completed(OperationCompletionInfo(success: false, message: "contents have not been checksum verified.")), rows: rows)
        #expect(outcome.counts.verified == 0)
        #expect(outcome.bytesVerified == nil)
        #expect(outcome.tone == .needsReview)
        #expect(outcome.issueLines == ["1 file result copied, not verified"])
    }

    // MARK: Actions

    // Plant: `primaryAction: needsRetry ? .retry : .newTransfer` (drop `canRetry &&`).
    @Test func retryIsPrimaryOnlyWhenItIsOffered() {
        let failedRows = [row("A001.mov", .failed, backup: backupA)]
        let issues = OperationState.completed(OperationCompletionInfo(success: false, message: "Operation completed with 1 issue"))
        #expect(make(state: issues, rows: failedRows, canRetry: true).primaryAction == .retry)
        #expect(make(state: issues, rows: failedRows, canRetry: false).primaryAction == .newTransfer)
    }

    // Plant: `primaryAction: canRetry ? .retry : .newTransfer`.
    @Test func verifiedAndCancelledLeadWithNewTransfer() {
        let done = make(state: .completed(OperationCompletionInfo(success: true, message: "Operation completed successfully")), rows: cleanRows)
        #expect(done.tone == .verified)
        #expect(done.primaryAction == .newTransfer)
        #expect(make(state: .cancelled, rows: partialRows).primaryAction == .newTransfer)
    }

    // Plant: in `TransferOutcomePresentation.make`, set `newTransferNote: nil`.
    @Test func newTransferSaysItKeepsTheBackups() {
        let outcome = make(state: .cancelled, rows: partialRows)
        #expect(outcome.newTransferNote == "Keeps the same 2 backups. Choose the next card.")
    }

    // Plant: in `statusLabel(for:)`, return `status` for every case.
    @Test func rowStatusIsPlainWords() {
        #expect(TransferOutcomePresentation.statusLabel(for: ResultOutcome.copiedUnverified.statusText) == "Copied, not verified")
        #expect(TransferOutcomePresentation.statusLabel(for: ResultOutcome.verified.statusText) == "Verified")
    }
}

/// Decision O-1, through the coordinator every platform's "New transfer" calls.
@MainActor
struct NewTransferSelectionTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Plant: delete `sourceURL = nil` from `SharedAppCoordinator.startNewTransfer()`.
    @Test func newTransferClearsTheSource() throws {
        let coordinator = SharedAppCoordinator(platformManager: MacOSPlatformManager.shared)
        let source = try makeDir()
        let backup = try makeDir()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: backup)
        }
        coordinator.sourceURL = source
        coordinator.destinationURLs = [backup]
        coordinator.operationState = .cancelled

        coordinator.startNewTransfer()

        #expect(coordinator.sourceURL == nil)
        #expect(coordinator.operationState == .notStarted)
        #expect(coordinator.results.isEmpty)
    }

    // Plant: add `destinationURLs = []` to `SharedAppCoordinator.startNewTransfer()`.
    @Test func newTransferKeepsTheBackups() throws {
        let coordinator = SharedAppCoordinator(platformManager: MacOSPlatformManager.shared)
        let backup = try makeDir()
        defer { try? FileManager.default.removeItem(at: backup) }
        coordinator.destinationURLs = [backup]
        coordinator.operationState = .completed(OperationCompletionInfo(success: true, message: "Operation completed successfully"))

        coordinator.startNewTransfer()

        #expect(coordinator.destinationURLs == [backup])
    }
}

/// Audit H12: one composed VoiceOver label per file result row, so a row
/// isn't four or five separate stops (icon, name, size, destination) with
/// no column header to say what a bare number means.
struct ResultRowAccessibilityLabelTests {
    private func row(status: ResultOutcome, size: Int64 = 2_048, destination: String?) -> ResultRow {
        ResultRow(path: "/Card/DCIM/A001.MOV", status: status.statusText, size: size, checksum: nil, destination: destination)
    }

    /// Plant: in `TransferOutcomePresentation.accessibilityLabel(for:)`,
    /// drop the status segment (`"\(name), \(size)"`).
    @Test func labelNamesFileStatusSizeAndDestination() {
        let size = ByteCountFormatter.string(fromByteCount: 2_048, countStyle: .file)
        let label = TransferOutcomePresentation.accessibilityLabel(for: row(status: .checksumMismatch, size: 2_048, destination: "Backup A"))
        #expect(label == "A001.MOV, Checksum mismatch, \(size), Backup A")
    }

    /// A row with no destination (still processing, or a legacy record)
    /// must not read a dangling comma.
    @Test func labelOmitsMissingDestination() {
        let size = ByteCountFormatter.string(fromByteCount: 2_048, countStyle: .file)
        let label = TransferOutcomePresentation.accessibilityLabel(for: row(status: .verified, destination: nil))
        #expect(label == "A001.MOV, Verified, \(size)")
    }

    /// Plant: in `TransferOutcomePresentation.accessibilityLabel(for:)`,
    /// call `row.status` directly instead of `statusLabel(for:)`, so the
    /// emoji status string is read aloud (audit L7).
    @Test func labelUsesPlainWordsNotEmoji() {
        let label = TransferOutcomePresentation.accessibilityLabel(for: row(status: .copiedUnverified, destination: "Backup B"))
        #expect(!label.contains("✅"))
        #expect(label.contains("Copied, not verified"))
    }
}
