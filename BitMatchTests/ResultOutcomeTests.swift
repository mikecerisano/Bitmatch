// ResultOutcomeTests.swift
// Promise 2: the text the engine writes for a result and the rule that
// decides whether that text is a success come from one typed outcome, so
// they cannot drift apart.
import Foundation
import Testing
@testable import BitMatch
import BitMatchEngine

struct ResultOutcomeTests {

    /// Fails if an outcome's `statusText` stops classifying back to itself,
    /// for example if "✅ Verified" is reworded without updating the parser.
    @Test func everyOutcomeRoundTripsThroughItsStatusText() {
        for outcome in ResultOutcome.allCases {
            #expect(ResultOutcome(statusText: outcome.statusText) == outcome, "\(outcome)")
            #expect(ResultRow.isSuccessStatus(outcome.statusText) == outcome.isSuccess, "\(outcome)")
        }
    }

    /// Fails if a mismatch or failure is ever counted as a success.
    @Test func onlyVerifiedAndCopiedAreSuccesses() {
        #expect(ResultOutcome.verified.isSuccess)
        #expect(ResultOutcome.copiedUnverified.isSuccess)
        #expect(!ResultOutcome.checksumMismatch.isSuccess)
        #expect(!ResultOutcome.failed.isSuccess)
        #expect(ResultOutcome.verified.isVerified)
        #expect(!ResultOutcome.copiedUnverified.isVerified)
    }

    /// The engine's rows carry the outcome's own text.
    @Test func fileResultsProduceOutcomeText() {
        let source = URL(fileURLWithPath: "/tmp/a")
        let destination = URL(fileURLWithPath: "/tmp/b")
        func result(success: Bool, valid: Bool?) -> FileOperationResult {
            FileOperationResult(
                sourceURL: source,
                destinationURL: destination,
                success: success,
                error: nil,
                fileSize: 1,
                verificationResult: valid.map {
                    VerificationResult(sourceChecksum: "a", destinationChecksum: $0 ? "a" : "b", matches: $0, checksumType: .sha256, processingTime: 0, fileSize: 1)
                },
                processingTime: 0
            )
        }
        #expect(result(success: true, valid: true).outcome == .verified)
        #expect(result(success: true, valid: false).outcome == .checksumMismatch)
        #expect(result(success: true, valid: nil).outcome == .copiedUnverified)
        #expect(result(success: false, valid: nil).outcome == .failed)
        #expect(result(success: true, valid: true).statusDescription == ResultOutcome.verified.statusText)
    }

    /// Saved history and other producers use older wording; the fail-safe
    /// legacy rule still classifies it, and unknown text is never a success.
    @Test func legacyAndUnknownTextStayFailSafe() {
        #expect(ResultRow.isSuccessStatus("✅ Files match - SHA256 verified"))
        #expect(!ResultRow.isSuccessStatus("⚠️ Checksum Mismatch"))
        #expect(!ResultRow.isSuccessStatus("Copied"))
        #expect(!ResultRow.isSuccessStatus(""))
    }

    private func row(_ outcome: ResultOutcome) -> ResultRow {
        ResultRow(path: "/card/\(UUID().uuidString)", status: outcome.statusText, size: 1, checksum: nil, destination: "Backup")
    }

    /// Promise 2 in the verdict itself, not only upstream: a run whose rows
    /// were copied but never verified is not green, even if the run reported
    /// success (audit C2). Fails if `CompletionVerdict.resolve` drops the
    /// copied-not-verified check.
    @Test func copiedButUnverifiedRowsAreNeverGreen() {
        let succeeded = OperationState.completed(OperationCompletionInfo(success: true, message: "done"))
        let allCopied = [row(.copiedUnverified), row(.copiedUnverified)]
        let mixed = [row(.verified), row(.copiedUnverified)]
        #expect(CompletionVerdict.resolve(state: succeeded, rows: allCopied, hasErrors: false, hasCriticalErrors: false) == .issues)
        #expect(CompletionVerdict.resolve(state: succeeded, rows: mixed, hasErrors: false, hasCriticalErrors: false) == .issues)
        #expect(CompletionVerdict.resolve(state: succeeded, rows: [row(.verified), row(.verified)], hasErrors: false, hasCriticalErrors: false) == .success)
    }
}
