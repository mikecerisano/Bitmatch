// TransferFinishNoticeTests.swift
import Testing
@testable import BitMatch
import BitMatchEngine

struct TransferFinishNoticeTests {
    private func notice(
        _ state: OperationState,
        issues: Int = 0,
        kind: TransferNotificationKind = .standaloneFinish
    ) -> TransferFinishNotice? {
        TransferFinishNotice.make(
            state: state,
            sourceName: "A001",
            backupNames: ["Shuttle A", "Shuttle B"],
            issueCount: issues,
            kind: kind
        )
    }

    /// Promise 2: only a real success says the card is safe to erase.
    /// Plant: drop `where info.success` from the first case.
    @Test func onlySuccessSaysSafeToErase() {
        #expect(notice(.completed(.init(success: true, message: ""))) == .init(
            title: "A001 is safe to erase",
            body: "Verified on Shuttle A and Shuttle B.",
            kind: .standaloneFinish
        ))
        let quick = notice(.completed(.init(success: false, message: "", copiedNotVerified: true)))
        #expect(quick?.title == "A001 was copied without checksum verification")
        #expect(quick?.kind == .standaloneFinish)
        #expect(quick?.title.contains("safe") == false)
        let attention = notice(.completed(.init(success: false, message: "")), issues: 3)
        #expect(attention?.body == "Do not erase the card.")
        #expect(attention?.kind == .attention)
        #expect(notice(.failed)?.title == "A001 failed")
        #expect(notice(.failed)?.kind == .attention)
    }

    /// A Quick run whose report or project failed is not "copied, not
    /// verified": the engine leaves `copiedNotVerified` off, so it needs
    /// attention. Plant: match `.completed` on Quick mode instead of
    /// `info.copiedNotVerified`.
    @Test func quickWithAnotherFailureNeedsAttention() {
        #expect(notice(.completed(.init(success: false, message: "report failed")))?.title == "A001 needs attention")
    }

    @Test func interruptedIsAttentionAndIdleSendsNothing() {
        #expect(notice(.cancelled) == .init(
            title: "A001 was interrupted",
            body: "Do not erase the card.",
            kind: .attention
        ))
        #expect(notice(.copying) == nil)
    }

    @Test func onlySafeToEraseUsesSafeOrVerifiedNotificationWords() {
        let unsafe = [
            notice(.completed(.init(success: false, message: "", copiedNotVerified: true))),
            notice(.completed(.init(success: false, message: "")), issues: 2),
            notice(.failed),
            notice(.cancelled)
        ]
        for notice in unsafe.compactMap({ $0 }) {
            let words = "\(notice.title) \(notice.body)".lowercased()
            #expect(!words.contains("safe to erase"))
            #expect(!words.contains("verified"))
        }

        let safe = notice(.completed(.init(success: true, message: "")))
        #expect(safe?.title.contains("safe to erase") == true)
        #expect(safe?.body.contains("Verified") == true)
    }

    @Test func successAndQuickUseTheExplicitQueuedKind() {
        #expect(notice(
            .completed(.init(success: true, message: "")),
            kind: .queuedCardSuccess
        )?.kind == .queuedCardSuccess)
        #expect(notice(
            .completed(.init(success: false, message: "", copiedNotVerified: true)),
            kind: .queuedCardSuccess
        )?.kind == .queuedCardSuccess)
    }

    @Test func queueFinishWordingIncludesItsTally() {
        #expect(TransferFinishNotice.queueFinished(
            tally: "3 safe to erase · 1 needs attention"
        ) == .init(
            title: "Queue finished: 3 safe to erase · 1 needs attention",
            body: "",
            kind: .queueFinished
        ))
    }
}
