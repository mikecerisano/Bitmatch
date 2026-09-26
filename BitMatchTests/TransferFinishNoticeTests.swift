// TransferFinishNoticeTests.swift
import Foundation
import Testing
@testable import BitMatch
import BitMatchEngine

struct TransferFinishNoticeTests {
    private let destinations = [
        URL(fileURLWithPath: "/Volumes/Shuttle A/Day 3"),
        URL(fileURLWithPath: "/Volumes/Shuttle B/Day 3"),
    ]

    private func notice(_ state: OperationState, issues: Int = 0) -> TransferFinishNotice? {
        TransferFinishNotice.make(state: state, sourceName: "A001", destinations: destinations, issueCount: issues)
    }

    /// Promise 2: only a real success says the card is safe to erase.
    /// Plant: drop `where info.success` from the first case.
    @Test func onlySuccessSaysSafeToErase() {
        #expect(notice(.completed(.init(success: true, message: ""))) == .init(
            title: "A001 is safe to erase.",
            body: "Verified on Shuttle A and Shuttle B."
        ))
        let quick = notice(.completed(.init(success: false, message: "", copiedNotVerified: true)))
        #expect(quick?.title == "A001 was copied without checksum verification.")
        #expect(quick?.title.contains("safe") == false)
        #expect(notice(.completed(.init(success: false, message: "")), issues: 3) == .init(
            title: "A001 needs attention.", body: "Do not erase the card."
        ))
        #expect(notice(.completed(.init(success: true, message: "")), issues: 1)?.title == "A001 needs attention.")
        #expect(notice(.failed) == .init(title: "A001 failed.", body: "Do not erase the card."))
    }

    /// A Quick run whose report or project failed is not "copied, not
    /// verified": the engine leaves `copiedNotVerified` off, so it needs
    /// attention. Plant: match `.completed` on Quick mode instead of
    /// `info.copiedNotVerified`.
    @Test func quickWithAnotherFailureNeedsAttention() {
        #expect(notice(.completed(.init(success: false, message: "report failed")))?.title == "A001 needs attention.")
    }

    @Test func interruptedWarnsAndActiveStatesSendNothing() {
        #expect(notice(.cancelled) == .init(title: "A001 was interrupted.", body: "Do not erase the card."))
        #expect(notice(.copying) == nil)
    }
}
