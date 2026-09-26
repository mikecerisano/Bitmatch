import Foundation
import Testing
@testable import BitMatch
import BitMatchEngine

/// The finish screen's core safety promise (docs/THESIS.md): "safe to
/// erase" — green, and Eject offered as the prominent action — belongs only
/// to a fully verified result. Quick mode, issues, a failure and a
/// cancellation must never say it, whatever else is true about the run.
struct CardEjectionPresentationTests {
    private let backupA = URL(fileURLWithPath: "/Volumes/A/Backup", isDirectory: true)

    private func row(_ outcome: ResultOutcome, name: String = "A001.mov") -> ResultRow {
        ResultRow(
            path: "/Card/\(name)",
            status: outcome.statusText,
            size: 100,
            checksum: outcome == .verified ? "abc" : nil,
            destination: backupA.lastPathComponent,
            destinationPath: backupA.appendingPathComponent(name).path
        )
    }

    private func make(state: OperationState, rows: [ResultRow]) -> TransferOutcomePresentation {
        TransferOutcomePresentation.make(
            state: state,
            rows: rows,
            destinations: [backupA],
            hasErrors: false,
            hasCriticalErrors: false,
            errorCount: 0,
            warningCount: 0,
            duration: 10,
            verificationMode: .standard,
            canRetry: true,
            canExport: true,
            sourceName: "SD001"
        )
    }

    // MARK: shouldAutoEject: verified only

    /// Plant: `shouldAutoEject(tone:) -> Bool { tone != .failed }`.
    /// Ran: failed (every non-failed tone wrongly auto-ejects, including
    /// `.copiedNotVerified` and `.needsReview`) → reverted → passes.
    @Test func onlyAFullyVerifiedResultAutoEjects() {
        #expect(TransferOutcomePresentation.shouldAutoEject(tone: .verified))
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: .copiedNotVerified))
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: .needsReview))
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: .failed))
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: .cancelled))
    }

    // MARK: A verified result is the only one that is safe to erase

    /// Plant: in `CompletionVerdictPresentation.make(_:cardName:...)`, use
    /// "is safe to erase" for `.copiedNotVerified` too.
    /// Ran: failed (Quick mode read as "SD001 is safe to erase") →
    /// reverted → passes.
    @Test func verifiedIsTheOnlyGreenSafeToEraseResult() {
        let verified = make(
            state: .completed(OperationCompletionInfo(success: true, message: "All files copied and verified")),
            rows: [row(.verified)]
        )
        #expect(verified.tone == .verified)
        #expect(verified.verdict.title == "SD001 is safe to erase")
        #expect(verified.ejectIsPrimaryAction)
        #expect(verified.ejectCautionLine == nil)
    }

    /// Quick mode: copied and not failed, but never checksum-verified.
    /// Plant: in `OutcomeTone.make`, map `.copiedNotVerified` to `.verified`.
    /// Ran: failed (Quick mode became green and offered eject as primary) →
    /// reverted → passes.
    @Test func quickModeIsNeverGreenOrPrimaryEject() {
        let quick = make(
            state: .completed(OperationCompletionInfo(success: true, message: "All files copied")),
            rows: [row(.copiedUnverified)]
        )
        #expect(quick.tone == .copiedNotVerified)
        #expect(quick.tone != .verified)
        #expect(quick.verdict.title == "SD001 copied, not verified")
        #expect(!quick.verdict.title.contains("safe to erase"))
        #expect(!quick.ejectIsPrimaryAction)
        #expect(quick.ejectCautionLine != nil)
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: quick.tone))
    }

    /// Plant: in `OutcomeTone.make`, map `.issues` to `.verified`.
    /// Ran: failed (a run with a failed file read as green and offered
    /// eject as primary) → reverted → passes.
    @Test func issuesAreNeverGreenOrPrimaryEject() {
        let issues = make(
            state: .completed(OperationCompletionInfo(success: false, message: "1 file failed")),
            rows: [row(.verified), row(.failed, name: "A002.mov")]
        )
        #expect(issues.tone == .needsReview)
        #expect(issues.verdict.title == "SD001 needs attention")
        #expect(!issues.ejectIsPrimaryAction)
        #expect(issues.ejectCautionLine != nil)
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: issues.tone))
    }

    /// Plant: in `OutcomeTone.make`, map `.failed` to `.verified`.
    /// Ran: failed (a failed transfer read as green and safe to erase) →
    /// reverted → passes.
    @Test func failedIsNeverGreenOrPrimaryEject() {
        let failed = make(state: .failed, rows: [row(.failed)])
        #expect(failed.tone == .failed)
        #expect(failed.verdict.title == "Transfer failed")
        #expect(!failed.ejectIsPrimaryAction)
        #expect(failed.ejectCautionLine != nil)
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: failed.tone))
    }

    /// A cancelled run keeps its partial results, but a partial copy is
    /// never "safe to erase" either.
    /// Plant: in `OutcomeTone.make`, drop the `state == .cancelled` guard.
    /// Ran: failed (a cancelled run stopped reading as `.cancelled` at all)
    /// → reverted → passes.
    @Test func cancelledIsNeverGreenOrPrimaryEject() {
        let cancelled = make(state: .cancelled, rows: [row(.verified)])
        #expect(cancelled.tone == .cancelled)
        #expect(!cancelled.ejectIsPrimaryAction)
        #expect(cancelled.ejectCautionLine != nil)
        #expect(!TransferOutcomePresentation.shouldAutoEject(tone: cancelled.tone))
    }
}
