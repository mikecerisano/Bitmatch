// TransferFinishNoticeTests.swift
import Testing
@testable import BitMatch
import BitMatchEngine

struct TransferFinishNoticeTests {
    private func notice(_ state: OperationState, issues: Int = 0) -> TransferFinishNotice? {
        TransferFinishNotice.make(state: state, sourceName: "A001", backupCount: 2, issueCount: issues)
    }

    /// Promise 2: only a real success says the card is safe to erase.
    /// Plant: drop `where info.success` from the first case.
    @Test func onlySuccessSaysSafeToErase() {
        #expect(notice(.completed(.init(success: true, message: ""))) == .init(title: "A001 is safe to erase", body: "Copied to 2 backups and verified."))
        let quick = notice(.completed(.init(success: false, message: "", copiedNotVerified: true)))
        #expect(quick?.title == "A001 copied, not verified")
        #expect(quick?.title.contains("safe") == false)
        #expect(notice(.completed(.init(success: false, message: "")), issues: 3)?.body == "3 files had problems. Open BitMatch to review.")
        #expect(notice(.failed)?.title == "A001 transfer failed")
    }

    /// A Quick run whose report or project failed is not "copied, not
    /// verified": the engine leaves `copiedNotVerified` off, so it needs
    /// attention. Plant: match `.completed` on Quick mode instead of
    /// `info.copiedNotVerified`.
    @Test func quickWithAnotherFailureNeedsAttention() {
        #expect(notice(.completed(.init(success: false, message: "report failed")))?.title == "A001 needs attention")
    }

    @Test func cancelledOrIdleSendsNothing() {
        #expect(notice(.cancelled) == nil)
        #expect(notice(.copying) == nil)
    }
}
