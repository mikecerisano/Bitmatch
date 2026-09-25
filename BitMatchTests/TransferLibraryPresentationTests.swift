import Foundation
import Testing
@testable import BitMatch

/// The Transfers library and its banner on Mac, iPad and iPhone (UI plan
/// step 4.4). Green is only for verified transfers (promise 2), and every
/// state differs by word and symbol, not colour alone.
struct TransferLibraryPresentationTests {
    private let allStates: [LocalTransferState] = [.queued, .running, .interrupted, .completed, .issues, .cancelled]

    // MARK: - State labels

    /// Plant: in `TransferLibraryPresentation.stateLabel`, change the
    /// `.interrupted` label's `tone: .warning` to `tone: .verified`.
    @Test func interruptedIsNotGreen() {
        let label = TransferLibraryPresentation.stateLabel(.interrupted, verificationMode: .standard)
        #expect(label.tone != .verified)
        #expect(label.tone == .warning)
    }

    /// Plant: in `TransferLibraryPresentation.stateLabel`, change
    /// `case .completed where verificationMode == .quick:` to
    /// `case .completed where verificationMode == .paranoid:`.
    @Test func completedQuickTransferIsNotGreen() {
        let label = TransferLibraryPresentation.stateLabel(.completed, verificationMode: .quick)
        #expect(label.tone != .verified)
        #expect(label.title != "Verified")
    }

    /// Only a completed, checksum-verified transfer is green.
    /// Plant: in `TransferLibraryPresentation.stateLabel`, change the
    /// `.issues` label's `tone: .warning` to `tone: .verified`.
    @Test func onlyCompletedIsGreen() {
        for state in allStates {
            let label = TransferLibraryPresentation.stateLabel(state, verificationMode: .standard)
            #expect((label.tone == .verified) == (state == .completed), "\(state)")
        }
    }

    /// Colour is never the only difference (accessibility audit M5).
    /// Plant: in `TransferLibraryPresentation.stateLabel`, change the
    /// `.interrupted` symbol to `"exclamationmark.triangle.fill"`.
    @Test func everyStateHasItsOwnWordAndSymbol() {
        let labels = allStates.map { TransferLibraryPresentation.stateLabel($0, verificationMode: .standard) }
        #expect(Set(labels.map(\.title)).count == allStates.count)
        #expect(Set(labels.map(\.systemImage)).count == allStates.count)
    }

    // MARK: - Actions

    /// Project cards are retried from their project, never from the library.
    /// Plant: in `TransferLibraryPresentation.actions(state:isProjectCard:generateASCMHL:)`,
    /// change `let canRetry = state.canRetry && !isProjectCard` to `let canRetry = state.canRetry`.
    @Test func projectCardCannotBeRetriedHere() {
        let actions = TransferLibraryPresentation.actions(state: .issues, isProjectCard: true, generateASCMHL: true)
        #expect(!actions.retry)
        #expect(!actions.reconnect)
        #expect(!actions.retryWithoutASCMHL)
        #expect(actions.showsProjectReviewNote)
    }

    /// A running transfer has no finished evidence to export.
    /// Plant: change `actions.export = state != .queued && state != .running`
    /// to `actions.export = state != .queued`.
    @Test func runningTransferCannotBeExported() {
        let running = TransferLibraryPresentation.actions(state: .running, isProjectCard: false, generateASCMHL: true)
        #expect(!running.export)
        let interrupted = TransferLibraryPresentation.actions(state: .interrupted, isProjectCard: false, generateASCMHL: true)
        #expect(interrupted.export)
        #expect(interrupted.retry)
        #expect(interrupted.reconnect)
        #expect(interrupted.retryWithoutASCMHL)
    }

    // MARK: - Search

    /// Plant: in `TransferLibraryPresentation.matches`, change
    /// `([title, summary, projectName] + backupNames)` to `[title, summary, projectName]`.
    @Test func searchFindsBackupFolderName() {
        #expect(TransferLibraryPresentation.matches(search: "shuttle", title: "A001", summary: "Verified",
                                                    projectName: "", backupNames: ["RAID", "Shuttle_02"]))
        #expect(!TransferLibraryPresentation.matches(search: "B002", title: "A001", summary: "Verified",
                                                     projectName: "", backupNames: ["RAID"]))
    }

    // MARK: - Banner

    /// The banner on all three platforms counts interrupted transfers.
    /// Plant: in `needsAttentionCount(states:)`, change
    /// `states.filter { $0 == .interrupted }.count` to `0`.
    @Test func bannerCountsInterruptedTransfers() {
        let count = TransferLibraryPresentation.needsAttentionCount(
            states: [.interrupted, .completed, .interrupted, .issues, .cancelled, .queued]
        )
        #expect(count == 2)
        #expect(TransferLibraryPresentation.bannerTitle(needsAttentionCount: count) == "2 interrupted transfers — review in Transfers")
        #expect(TransferLibraryPresentation.bannerTitle(needsAttentionCount: 1) == "Interrupted transfer — review in Transfers")
    }

    /// Plant: in `bannerTitle(needsAttentionCount:)`, change `case ..<1: return nil`
    /// to `case ..<0: return nil`.
    @Test func noBannerWhenNothingIsInterrupted() {
        let count = TransferLibraryPresentation.needsAttentionCount(states: [.completed, .issues, .cancelled])
        #expect(count == 0)
        #expect(TransferLibraryPresentation.bannerTitle(needsAttentionCount: count) == nil)
    }
}
