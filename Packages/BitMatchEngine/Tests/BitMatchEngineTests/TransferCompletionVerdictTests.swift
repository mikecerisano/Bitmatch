// TransferCompletionVerdictTests.swift
// Promise 2: success only when every file on every backup verified, and
// the message says why not. TransferCompletion.verdict is a pure function,
// so each rule is checked on its own here; PlatformVerdictParityTests
// checks the same verdict through a real run on each platform.
import Foundation
import Testing
@testable import BitMatchEngine

struct TransferCompletionVerdictTests {
    private let verified = ResultRow(path: "/c/A.MXF", status: ResultOutcome.verified.statusText,
                                     size: 1, checksum: "x", destination: "SSD")
    private let copied = ResultRow(path: "/c/A.MXF", status: ResultOutcome.copiedUnverified.statusText,
                                   size: 1, checksum: nil, destination: "SSD")
    private let failed = ResultRow(path: "/c/B.MXF", status: ResultOutcome.failed.statusText,
                                   size: 0, checksum: nil, destination: "SSD")
    private let ordinary = TransferCompletion.ProjectGate(didPersist: true, locallySafe: nil)

    private func verdict(
        _ rows: [ResultRow], mode: VerificationMode = .standard, mhl: Bool = false,
        handoff: [String] = [], report: String? = nil,
        project: TransferCompletion.ProjectGate? = nil
    ) -> TransferCompletion.Verdict {
        TransferCompletion.verdict(rows: rows, mode: mode, generateASCMHL: mhl, handoffIssues: handoff,
                                   reportIssue: report, project: project ?? ordinary)
    }

    @Test func everyFileVerifiedIsSuccess() {
        #expect(verdict([verified, verified]) == .init(success: true, message: "All files copied and verified"))
        #expect(verdict([verified], mhl: true) == .init(success: true, message: "All files copied and verified; ASC MHL handoff records saved"))
    }

    /// Plant: in `TransferCompletion.verdict`, drop `mode != .quick`.
    @Test func quickIsNeverSuccess() {
        #expect(verdict([copied], mode: .quick) == .init(success: false, message: "All files copied. Not verified: Quick mode only compares file sizes.", copiedNotVerified: true))
    }

    /// "Copied, not verified" only when Quick was the one gap: a failed
    /// file, a lost report, a handoff failure or an unsaved project still
    /// reads as needing attention. Plant: in `TransferCompletion.verdict`,
    /// set `copiedNotVerified: mode == .quick`.
    @Test func copiedNotVerifiedOnlyWhenQuickIsTheOnlyGap() {
        #expect(verdict([copied], mode: .quick).copiedNotVerified)
        #expect(!verdict([copied, failed], mode: .quick).copiedNotVerified)
        #expect(!verdict([], mode: .quick).copiedNotVerified)
        #expect(!verdict([copied], mode: .quick, report: "disk full").copiedNotVerified)
        #expect(!verdict([copied], mode: .quick, handoff: ["SSD: disk full"]).copiedNotVerified)
        #expect(!verdict([copied], mode: .quick, project: .init(didPersist: false, locallySafe: nil)).copiedNotVerified)
        #expect(!verdict([verified]).copiedNotVerified)
    }

    /// Promise 2 in the engine: outside Quick, a copied-but-unverified row
    /// is never a success, so nothing reading `success` can show green.
    /// Plant: in `TransferCompletion.verdict`, drop `&& everyRowVerified`.
    @Test func unverifiedRowOutsideQuickIsNotSuccess() {
        let result = verdict([verified, copied])
        #expect(!result.success)
        #expect(!result.copiedNotVerified)
        #expect(result.message == "All files copied")
    }

    @Test func anyIssueOrNoFilesIsNotSuccess() {
        #expect(verdict([verified, failed]) == .init(success: false, message: "1 file failed"))
        #expect(verdict([]) == .init(success: false, message: "No files were copied"))
    }

    @Test func handoffReportAndProjectFailuresAreNotSuccess() {
        #expect(verdict([verified], mhl: true, handoff: ["SSD: ASC MHL — disk full"]) == .init(success: false, message: "All files copied and verified; SSD: ASC MHL — disk full"))
        #expect(verdict([verified], report: "disk full") == .init(success: false, message: "All files copied and verified; the report could not be saved: disk full"))
        #expect(verdict([verified], project: .init(didPersist: false, locallySafe: nil)) == .init(success: false, message: "All files copied and verified; the project record was not saved"))
        #expect(verdict([verified], project: .init(didPersist: true, locallySafe: false)) == .init(success: false, message: "All files copied and verified; the card is not yet verified on all the project's backups"))
        #expect(verdict([verified], project: .init(didPersist: true, locallySafe: true)).success)
    }
}
