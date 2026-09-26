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
        #expect(verdict([verified, verified]) == .init(success: true, message: "Operation completed successfully"))
        #expect(verdict([verified], mhl: true) == .init(success: true, message: "Operation completed successfully; ASC MHL handoff records saved"))
    }

    /// Plant: in `TransferCompletion.verdict`, drop `mode != .quick`.
    @Test func quickIsNeverSuccess() {
        #expect(verdict([copied], mode: .quick) == .init(success: false, message: "Operation completed successfully; contents have not been checksum verified."))
    }

    @Test func anyIssueOrNoFilesIsNotSuccess() {
        #expect(verdict([verified, failed]) == .init(success: false, message: "Operation completed with 1 issue"))
        #expect(verdict([]) == .init(success: false, message: "No files were verified"))
    }

    @Test func handoffReportAndProjectFailuresAreNotSuccess() {
        #expect(verdict([verified], mhl: true, handoff: ["SSD: ASC MHL — disk full"]) == .init(success: false, message: "Operation completed successfully; SSD: ASC MHL — disk full"))
        #expect(verdict([verified], report: "disk full") == .init(success: false, message: "Operation completed successfully; report export failed: disk full"))
        #expect(verdict([verified], project: .init(didPersist: false, locallySafe: nil)) == .init(success: false, message: "Operation completed successfully; photographer lifecycle finalization failed"))
        #expect(verdict([verified], project: .init(didPersist: true, locallySafe: false)) == .init(success: false, message: "Operation completed successfully; photographer verification is incomplete"))
        #expect(verdict([verified], project: .init(didPersist: true, locallySafe: true)).success)
    }
}
