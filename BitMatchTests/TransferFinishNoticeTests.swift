// TransferFinishNoticeTests.swift
import Testing
@testable import BitMatch
import BitMatchEngine

struct TransferFinishNoticeTests {
    private func notice(_ state: OperationState, issues: Int = 0, mode: VerificationMode = .standard) -> TransferFinishNotice? {
        TransferFinishNotice.make(state: state, sourceName: "A001", backupCount: 2, issueCount: issues, mode: mode)
    }

    /// Promise 2: only a real success says the card is safe to erase.
    /// Plant: drop `where info.success` from the first case.
    @Test func onlySuccessSaysSafeToErase() {
        #expect(notice(.completed(.init(success: true, message: ""))) == .init(title: "A001 is safe to erase", body: "Copied to 2 backups and verified."))
        let quick = notice(.completed(.init(success: false, message: "")), mode: .quick)
        #expect(quick?.title == "A001 copied, not verified")
        #expect(quick?.title.contains("safe") == false)
        #expect(notice(.completed(.init(success: false, message: "")), issues: 3)?.body == "3 files had problems. Open BitMatch to review.")
        #expect(notice(.failed)?.title == "A001 transfer failed")
    }

    @Test func cancelledOrIdleSendsNothing() {
        #expect(notice(.cancelled) == nil)
        #expect(notice(.copying) == nil)
    }
}
