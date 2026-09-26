import Foundation
import BitMatchEngine

/// What the Transfers library shows for each journal record, and which
/// records raise the "review in Transfers" banner on Mac, iPad and iPhone.
/// Pure values, so every platform shows the same state the same way.
enum TransferLibraryPresentation {

    /// A record's state as a word, a symbol and a tone. The word and symbol
    /// differ for every state, so colour is never the only signal. Green
    /// (`.verified`) is only for a completed transfer whose copies were
    /// checksum-verified.
    struct StateLabel: Equatable, Sendable {
        let title: String
        let systemImage: String
        let tone: ResultStatusTone
    }

    static func stateLabel(_ state: LocalTransferState, verificationMode: VerificationMode) -> StateLabel {
        switch state {
        case .completed where verificationMode == .quick:
            // The journal already files Quick runs as `.issues`; this keeps an
            // older or hand-edited record from turning green.
            return StateLabel(title: "Copied, not verified", systemImage: "doc.on.doc", tone: .warning)
        case .completed:
            return StateLabel(title: "Verified", systemImage: "checkmark.circle.fill", tone: .verified)
        case .issues:
            return StateLabel(title: "Needs review", systemImage: "exclamationmark.triangle.fill", tone: .warning)
        case .interrupted:
            return StateLabel(title: "Interrupted", systemImage: "pause.circle.fill", tone: .warning)
        case .cancelled:
            return StateLabel(title: "Cancelled", systemImage: "xmark.circle", tone: .neutral)
        case .queued:
            return StateLabel(title: "Queued", systemImage: "clock", tone: .neutral)
        case .running:
            return StateLabel(title: "Copying", systemImage: "arrow.triangle.2.circlepath", tone: .inProgress)
        }
    }

    /// The buttons a record offers. Mirrors the journal's own rules
    /// (`LocalTransferState.canRetry`, project cards retried from their project).
    struct Actions: Equatable, Sendable {
        var removeFromQueue = false
        var reconnect = false
        var retry = false
        var retryWithoutASCMHL = false
        var export = false
        /// Project cards are reviewed and retried in their project, not here.
        var showsProjectReviewNote = false
    }

    static func actions(state: LocalTransferState, isProjectCard: Bool, generateASCMHL: Bool) -> Actions {
        var actions = Actions()
        let canRetry = state.canRetry && !isProjectCard
        if state == .queued {
            actions.removeFromQueue = true
            actions.reconnect = !isProjectCard
        } else if canRetry {
            actions.retry = true
            actions.reconnect = true
            actions.retryWithoutASCMHL = generateASCMHL
        }
        actions.export = state != .queued && state != .running
        actions.showsProjectReviewNote = isProjectCard && state != .completed
        return actions
    }

    static func actions(for record: LocalTransferRecord) -> Actions {
        actions(state: record.state, isProjectCard: record.projectID != nil, generateASCMHL: record.generateASCMHL)
    }

    /// Queue shows work that is waiting or recoverable; History shows everything.
    static func isVisible(state: LocalTransferState, showHistory: Bool) -> Bool {
        showHistory || state.showsInQueue
    }

    /// Case-insensitive match on the card, summary, project and backup folder names.
    static func matches(search: String, title: String, summary: String, projectName: String, backupNames: [String]) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([title, summary, projectName] + backupNames)
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)
    }

    static func visibleRecords(_ records: [LocalTransferRecord], showHistory: Bool, search: String) -> [LocalTransferRecord] {
        records.filter { record in
            isVisible(state: record.state, showHistory: showHistory)
                && matches(search: search, title: record.title, summary: record.summary,
                           projectName: record.reportSettings.projectName,
                           backupNames: record.destinations.map { $0.url.lastPathComponent })
        }
    }

    static func recent(_ records: [LocalTransferRecord], limit: Int) -> [LocalTransferRecord] {
        guard limit > 0 else { return [] }
        return Array(records
            .filter { $0.state != .queued && $0.state != .running }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit))
    }

    /// The counts shown on the Queue/History segmented control.
    static func tabCounts(_ records: [LocalTransferRecord]) -> (queue: Int, history: Int) {
        let queue = records.filter { $0.state.showsInQueue }.count
        return (queue, records.count)
    }

    /// The row's secondary line, next to the date: how many backups and how
    /// many files this transfer covers. Singular/plural for both nouns.
    static func detailLine(destinationCount: Int, fileCount: Int) -> String {
        let backups = destinationCount == 1 ? "1 backup" : "\(destinationCount) backups"
        let files = fileCount == 1 ? "1 file" : "\(fileCount) files"
        return "\(backups) · \(files)"
    }

    // MARK: - Banner

    /// How many transfers the banner on every platform asks the user to
    /// review. Only interrupted runs count: nobody has seen their outcome,
    /// and their copies are unchecked. A run that finished with issues showed
    /// its verdict on the completion screen already, and it stays in the queue.
    static func needsAttentionCount(states: [LocalTransferState]) -> Int {
        states.filter { $0 == .interrupted }.count
    }

    static func needsAttentionCount(_ records: [LocalTransferRecord]) -> Int {
        needsAttentionCount(states: records.map(\.state))
    }

    /// Banner text, or nil when there is nothing to review.
    static func bannerTitle(needsAttentionCount count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "Interrupted transfer — review in Transfers"
        default: return "\(count) interrupted transfers — review in Transfers"
        }
    }
}
