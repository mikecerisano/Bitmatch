import Foundation
import Testing
@testable import BitMatch
import BitMatchEngine

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

    // MARK: - Tab counts

    /// The Queue/History segmented control's counts (UI plan step: compact
    /// rows). History always counts every record; Queue only the states that
    /// show there.
    /// Plant: in `tabCounts(_:)`, change `records.filter { $0.state.showsInQueue }.count`
    /// to `records.count`.
    @Test func tabCountsSplitQueueFromHistory() {
        let states: [LocalTransferState] = [.queued, .running, .interrupted, .completed, .issues, .cancelled]
        let records = states.map { PresentationTestSupport.record(state: $0) }
        let counts = TransferLibraryPresentation.tabCounts(records)
        #expect(counts.history == 6)
        #expect(counts.queue == 5) // every state but .completed shows in the queue
    }

    // MARK: - Recent transfers

    @Test func recentTransfersExcludeQueuedAndRunningBeforeLimiting() {
        let states: [LocalTransferState] = [.completed, .interrupted, .issues, .cancelled, .queued, .running]
        let records = states.enumerated().map { index, state in
            PresentationTestSupport.record(state: state, createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        let recent = TransferLibraryPresentation.recent(records, limit: 3)
        #expect(recent.map(\.id) == [records[3].id, records[2].id, records[1].id])
    }

    @Test func recentTransfersSortUnorderedHistoryNewestFirst() {
        let oldest = PresentationTestSupport.record(state: .completed, createdAt: Date(timeIntervalSince1970: 1))
        let newest = PresentationTestSupport.record(state: .issues, createdAt: Date(timeIntervalSince1970: 3))
        let middle = PresentationTestSupport.record(state: .interrupted, createdAt: Date(timeIntervalSince1970: 2))
        let recent = TransferLibraryPresentation.recent([middle, oldest, newest], limit: 10)
        #expect(recent.map(\.id) == [newest.id, middle.id, oldest.id])
        #expect(TransferLibraryPresentation.recent([oldest, newest, middle], limit: 1).map(\.id) == [newest.id])
    }

    @Test func recentTransfersHandleEmptyHistoryAndNonpositiveLimits() {
        #expect(TransferLibraryPresentation.recent([], limit: 3).isEmpty)
        let records = [PresentationTestSupport.record(state: .completed)]
        #expect(TransferLibraryPresentation.recent(records, limit: 0).isEmpty)
        #expect(TransferLibraryPresentation.recent(records, limit: -1).isEmpty)
        let active = [LocalTransferState.queued, .running].map { PresentationTestSupport.record(state: $0) }
        #expect(TransferLibraryPresentation.recent(active, limit: 3).isEmpty)
    }

    // MARK: - Detail line

    /// Plant: in `detailLine(destinationCount:fileCount:)`, change
    /// `destinationCount == 1 ? "1 backup" : "\(destinationCount) backups"` to
    /// always return `"\(destinationCount) backups"`.
    @Test func detailLineSingularizesOneBackupAndOneFile() {
        #expect(TransferLibraryPresentation.detailLine(destinationCount: 1, fileCount: 1) == "1 backup · 1 file")
        #expect(TransferLibraryPresentation.detailLine(destinationCount: 2, fileCount: 128) == "2 backups · 128 files")
    }
}

/// Shared minimal fixtures for these tests.
private enum PresentationTestSupport {
    static func record(state: LocalTransferState, createdAt: Date = Date()) -> LocalTransferRecord {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try! LocalTransferResource(url: root)
        var record = LocalTransferRecord(
            id: UUID(), createdAt: createdAt, source: source, destinations: [source],
            verificationMode: .standard, cameraSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(), generateASCMHL: true, projectID: nil
        )
        record.state = state
        return record
    }
}
