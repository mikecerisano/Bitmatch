import Foundation
import Combine

/// The app's observable view of the transfer journal. Every call goes to the
/// engine's `TransferJournal`, and `records` / `persistenceError` are
/// republished after it, whether it succeeded or threw.
@MainActor
final class LocalTransferJournal: ObservableObject {
    @Published private(set) var records: [LocalTransferRecord] = []
    @Published private(set) var persistenceError: String?
    let store: TransferJournal

    init(fileURL: URL? = nil) {
        store = TransferJournal(fileURL: fileURL)
        refresh()
    }

    private func refresh() {
        records = store.records
        persistenceError = store.persistenceError
    }

    @discardableResult
    func enqueue(sourceURL: URL, destinationURLs: [URL], verificationMode: VerificationMode,
                 cameraSettings: CameraLabelSettings, reportSettings: ReportPrefs, generateASCMHL: Bool = true, projectID: UUID? = nil) throws -> UUID {
        defer { refresh() }
        return try store.enqueue(sourceURL: sourceURL, destinationURLs: destinationURLs, verificationMode: verificationMode,
                                 cameraSettings: cameraSettings, reportSettings: reportSettings,
                                 generateASCMHL: generateASCMHL, projectID: projectID)
    }

    /// A retry is a new attempt, preserving the previous attempt and its evidence.
    @discardableResult
    func requeue(id: UUID, generateASCMHL: Bool? = nil) throws -> UUID {
        defer { refresh() }
        return try store.requeue(id: id, generateASCMHL: generateASCMHL)
    }

    func prepareToRun(id: UUID) throws -> LocalTransferAccess {
        try store.prepareToRun(id: id)
    }

    /// Indexes into `[source] + destinations` whose stored access no longer
    /// resolves to the original folder (stale bookmark, unplugged drive).
    func staleResourceIndexes(id: UUID) throws -> [Int] {
        try store.staleResourceIndexes(id: id)
    }

    /// Refreshes one stored location after access expired; see `TransferJournal.reauthorize`.
    func reauthorize(id: UUID, resourceIndex: Int, newURL: URL) throws {
        defer { refresh() }
        try store.reauthorize(id: id, resourceIndex: resourceIndex, newURL: newURL)
    }

    func markRunning(id: UUID) throws {
        defer { refresh() }
        try store.markRunning(id: id)
    }

    func finish(id: UUID, results: [ResultRow], summary: String, hadIssues: Bool) throws {
        defer { refresh() }
        try store.finish(id: id, results: results, summary: summary, hadIssues: hadIssues)
    }

    func interrupt(id: UUID, summary: String, results: [ResultRow]? = nil) throws {
        defer { refresh() }
        try store.interrupt(id: id, summary: summary, results: results)
    }

    func cancel(id: UUID, summary: String = "Cancelled", results: [ResultRow]? = nil) throws {
        defer { refresh() }
        try store.cancel(id: id, summary: summary, results: results)
    }
}
