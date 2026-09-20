import Foundation
import Combine
import Darwin

enum LocalTransferState: String, Codable {
    case queued, running, interrupted, completed, issues, cancelled

    var canRetry: Bool { self == .queued || self == .interrupted || self == .issues || self == .cancelled }

    /// States shown under the Queue tab. Cancelled transfers stay here because
    /// they are retryable; surfacing Retry in the queue keeps recovery discoverable.
    var showsInQueue: Bool { self == .queued || self == .running || self == .interrupted || self == .issues || self == .cancelled }
}

/// The original selection, including its identity. Never substitute a new disk at the same path.
struct LocalTransferResource: Codable {
    let url: URL
    let bookmark: Data
    let volumeID: String?
    let resourceID: String?

    init(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .volumeUUIDStringKey, .fileResourceIdentifierKey])
        guard values.isDirectory == true else { throw LocalTransferJournalError.unavailable(url.lastPathComponent) }
        self.url = url
        volumeID = values.volumeUUIDString
        resourceID = values.fileResourceIdentifier.map { String(describing: $0) }
        #if os(macOS)
        bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    fileprivate func resolve() throws -> URL {
        var stale = false
        #if os(macOS)
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        guard !stale else { throw LocalTransferJournalError.unavailable(url.lastPathComponent) }
        return resolved
    }

    fileprivate func validate(_ resolved: URL) throws {
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .volumeUUIDStringKey, .fileResourceIdentifierKey])
        // A bookmark keeps the selected URL reachable, but it is not enough to
        // prove that a path still names the original folder. Require both
        // identity components before using a persisted location. Treating a
        // missing component as a wildcard would allow a replacement folder on
        // the same volume (or a matching file ID on another volume) through.
        guard volumeID != nil, resourceID != nil else {
            throw LocalTransferJournalError.unverifiableIdentity(name: url.lastPathComponent)
        }
        guard let volumeID,
              let resourceID,
              let resolvedVolumeID = values.volumeUUIDString,
              let resolvedResourceID = values.fileResourceIdentifier,
              values.isDirectory == true,
              resolvedVolumeID == volumeID,
              String(describing: resolvedResourceID) == resourceID,
              FileManager.default.isReadableFile(atPath: resolved.path) else {
            throw LocalTransferJournalError.unavailable(url.lastPathComponent)
        }
    }
}

struct LocalTransferRecord: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    /// Refreshable access tokens for the same immutable selection. Reauthorization
    /// replaces these only after the original volume and folder identity match.
    var source: LocalTransferResource
    var destinations: [LocalTransferResource]
    let verificationMode: VerificationMode
    let cameraSettings: CameraLabelSettings
    let reportSettings: ReportPrefs
    let generateASCMHL: Bool
    let projectID: UUID?
    var state: LocalTransferState = .queued
    var startedAt: Date?
    var endedAt: Date?
    var summary: String = "Ready to copy"
    var results: [ResultRow] = []

    var title: String { source.url.lastPathComponent }
    var canRetry: Bool { state.canRetry && projectID == nil }

    init(id: UUID, createdAt: Date, source: LocalTransferResource, destinations: [LocalTransferResource],
         verificationMode: VerificationMode, cameraSettings: CameraLabelSettings, reportSettings: ReportPrefs,
         generateASCMHL: Bool = true, projectID: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.destinations = destinations
        self.verificationMode = verificationMode
        self.cameraSettings = cameraSettings
        self.reportSettings = reportSettings
        self.generateASCMHL = generateASCMHL
        self.projectID = projectID
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, source, destinations, verificationMode, cameraSettings, reportSettings
        case generateASCMHL, projectID, state, startedAt, endedAt, summary, results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = try c.decode(LocalTransferResource.self, forKey: .source)
        destinations = try c.decode([LocalTransferResource].self, forKey: .destinations)
        verificationMode = try c.decode(VerificationMode.self, forKey: .verificationMode)
        cameraSettings = try c.decode(CameraLabelSettings.self, forKey: .cameraSettings)
        reportSettings = try c.decode(ReportPrefs.self, forKey: .reportSettings)
        generateASCMHL = try c.decodeIfPresent(Bool.self, forKey: .generateASCMHL) ?? true
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        state = try c.decode(LocalTransferState.self, forKey: .state)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        summary = try c.decode(String.self, forKey: .summary)
        results = try c.decode([ResultRow].self, forKey: .results)
    }
    var issueCount: Int { results.filter { !$0.isSuccessStatus }.count }
}

/// Retain this lease for the entire operation, then release it (or let it deinitialize).
final class LocalTransferAccess {
    let sourceURL: URL
    let destinationURLs: [URL]
    private var scopedURLs: [URL]

    fileprivate init(sourceURL: URL, destinationURLs: [URL], scopedURLs: [URL]) {
        self.sourceURL = sourceURL
        self.destinationURLs = destinationURLs
        self.scopedURLs = scopedURLs
    }

    func release() {
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs.removeAll()
    }

    deinit { release() }
}

enum LocalTransferJournalError: LocalizedError {
    case unavailable(String), invalidState, missingDestinations, unreadableJournal(String), busy
    case identityMismatch(name: String), unverifiableIdentity(name: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let name): return "Reconnect or reselect \(name). Its original folder could not be confirmed."
        case .busy: return "Transfer history is already open in another app instance. Close it before starting another transfer."
        case .invalidState: return "This transfer cannot be started in its current state."
        case .missingDestinations: return "Choose at least one backup."
        case .unreadableJournal(let message): return "Transfer history could not be loaded: \(message)"
        case .identityMismatch(let name):
            return "\(name) is not the original folder. Pick the original drive and folder, or start a new transfer instead."
        case .unverifiableIdentity(let name):
            return "The original identity of \(name) was never recorded, so it cannot be confirmed. Start a new transfer instead."
        }
    }
}

/// Durable foreground queue and history shared by Mac, iPhone, and iPad.
/// All mutations reach disk before becoming visible. This store never starts work itself.
@MainActor
final class LocalTransferJournal: ObservableObject {
    @Published private(set) var records: [LocalTransferRecord] = []
    @Published private(set) var persistenceError: String?
    private let fileURL: URL
    private var loadFailed = false
    private var lockDescriptor: Int32 = -1

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BitMatch/transfer-history.json")
        do {
            try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let descriptor = Darwin.open(self.fileURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw LocalTransferJournalError.unreadableJournal("Could not lock the history file") }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(descriptor)
                throw LocalTransferJournalError.busy
            }
            lockDescriptor = descriptor
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                records = try JSONDecoder().decode([LocalTransferRecord].self, from: Data(contentsOf: self.fileURL))
                var recovered = records
                for index in recovered.indices where recovered[index].state == .running {
                    recovered[index].state = .interrupted
                    recovered[index].summary = "Interrupted. Reconnect the original folders and retry to check the copies."
                }
                // Publish interruption even if the recovery write fails; never display a stale running claim.
                records = recovered
                try persist(recovered)
            }
        } catch {
            loadFailed = true
            persistenceError = error.localizedDescription
        }
    }

    deinit {
        if lockDescriptor >= 0 {
            flock(lockDescriptor, LOCK_UN)
            Darwin.close(lockDescriptor)
        }
    }

    @discardableResult
    func enqueue(sourceURL: URL, destinationURLs: [URL], verificationMode: VerificationMode,
                 cameraSettings: CameraLabelSettings, reportSettings: ReportPrefs, generateASCMHL: Bool = true, projectID: UUID? = nil) throws -> UUID {
        guard !destinationURLs.isEmpty else { throw LocalTransferJournalError.missingDestinations }
        let record = LocalTransferRecord(id: UUID(), createdAt: Date(), source: try LocalTransferResource(url: sourceURL),
                                         destinations: try destinationURLs.map(LocalTransferResource.init(url:)),
                                         verificationMode: verificationMode, cameraSettings: cameraSettings, reportSettings: reportSettings,
                                         generateASCMHL: generateASCMHL, projectID: projectID)
        try commit([record] + records)
        return record.id
    }

    /// A retry is a new attempt, preserving the previous attempt and its evidence.
    @discardableResult
    func requeue(id: UUID, generateASCMHL: Bool? = nil) throws -> UUID {
        guard let original = records.first(where: { $0.id == id }), original.canRetry,
              original.state != .queued else { throw LocalTransferJournalError.invalidState }
        let access = try prepareToRun(id: id)
        defer { access.release() }
        let retry = LocalTransferRecord(id: UUID(), createdAt: Date(), source: original.source,
                                        destinations: original.destinations, verificationMode: original.verificationMode,
                                        cameraSettings: original.cameraSettings, reportSettings: original.reportSettings,
                                        generateASCMHL: generateASCMHL ?? original.generateASCMHL, projectID: original.projectID)
        try commit([retry] + records)
        return retry.id
    }

    func prepareToRun(id: UUID) throws -> LocalTransferAccess {
        guard let record = records.first(where: { $0.id == id }), (record.state == .queued || record.canRetry) else {
            throw LocalTransferJournalError.invalidState
        }
        var scopedURLs: [URL] = []
        do {
            let resources = [record.source] + record.destinations
            var resolvedURLs: [URL] = []
            for resource in resources {
                let resolved = try resource.resolve()
                if resolved.startAccessingSecurityScopedResource() { scopedURLs.append(resolved) }
                try resource.validate(resolved)
                resolvedURLs.append(resolved)
            }
            return LocalTransferAccess(sourceURL: resolvedURLs[0], destinationURLs: Array(resolvedURLs.dropFirst()), scopedURLs: scopedURLs)
        } catch {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Indexes into `[source] + destinations` whose stored access no longer
    /// resolves to the original folder (stale bookmark, unplugged drive).
    func staleResourceIndexes(id: UUID) throws -> [Int] {
        guard let record = records.first(where: { $0.id == id }) else {
            throw LocalTransferJournalError.invalidState
        }
        var stale: [Int] = []
        for (index, resource) in ([record.source] + record.destinations).enumerated() {
            do {
                let resolved = try resource.resolve()
                let scoped = resolved.startAccessingSecurityScopedResource()
                defer { if scoped { resolved.stopAccessingSecurityScopedResource() } }
                try resource.validate(resolved)
            } catch {
                stale.append(index)
            }
        }
        return stale
    }

    /// Refreshes one stored location after access expired. The replacement must
    /// be the original volume and folder: anything else is rejected rather than
    /// silently substituted. Earlier attempts and their evidence are untouched.
    func reauthorize(id: UUID, resourceIndex: Int, newURL: URL) throws {
        guard var record = records.first(where: { $0.id == id }),
              record.state == .queued || record.canRetry else {
            throw LocalTransferJournalError.invalidState
        }
        let resources = [record.source] + record.destinations
        guard resources.indices.contains(resourceIndex) else {
            throw LocalTransferJournalError.invalidState
        }
        // URL objects cache resource values: drop the cache so the identity reads
        // below observe the folder as it is now, not a deleted predecessor.
        var uncachedURL = newURL
        uncachedURL.removeAllCachedResourceValues()
        let refreshed = try LocalTransferResource(url: uncachedURL)
        try validateReauthorization(original: resources[resourceIndex], recordCreatedAt: record.createdAt,
                                    refreshed: refreshed, refreshedURL: uncachedURL, name: newURL.lastPathComponent)
        if resourceIndex == 0 {
            record.source = refreshed
        } else {
            record.destinations[resourceIndex - 1] = refreshed
        }
        try commit(records.map { $0.id == id ? record : $0 })
    }

    private func validateReauthorization(original: LocalTransferResource, recordCreatedAt: Date,
                                         refreshed: LocalTransferResource, refreshedURL: URL, name: String) throws {
        // Reauthorization changes the access token, so a partial identity is
        // unsafe: it cannot establish both the original volume and folder.
        guard original.volumeID != nil, original.resourceID != nil,
              refreshed.volumeID != nil, refreshed.resourceID != nil else {
            throw LocalTransferJournalError.unverifiableIdentity(name: name)
        }
        let volumeOK = original.volumeID == refreshed.volumeID
        let resourceOK = original.resourceID == refreshed.resourceID
        guard volumeOK && resourceOK else {
            throw LocalTransferJournalError.identityMismatch(name: name)
        }
        // Keep a readable, directory-only replacement in the journal. Without
        // this check a matching but inaccessible picker result would look
        // connected until the next queue attempt.
        try refreshed.validate(refreshedURL)
        // File identifiers may be reused once a folder is deleted, so a recreated
        // folder at the same path can present matching identifiers. The original
        // folder necessarily predates the transfer record; anything younger is a
        // replacement, not the original.
        if let birthtime = try? refreshedURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
           birthtime > recordCreatedAt {
            throw LocalTransferJournalError.identityMismatch(name: name)
        }
    }

    func markRunning(id: UUID) throws {
        guard !records.contains(where: { $0.state == .running }) else { throw LocalTransferJournalError.invalidState }
        try update(id: id) { record in
            guard record.state == .queued || record.canRetry else { throw LocalTransferJournalError.invalidState }
            record.state = .running
            record.startedAt = Date()
            record.endedAt = nil
            record.summary = "Copying and verifying"
        }
    }

    func finish(id: UUID, results: [ResultRow], summary: String, hadIssues: Bool) throws {
        try update(id: id) { record in
            guard record.state == .running else { throw LocalTransferJournalError.invalidState }
            record.results = results
            record.state = hadIssues || results.isEmpty || results.contains(where: { !$0.isSuccessStatus }) ? .issues : .completed
            record.summary = record.verificationMode == .quick ? "Copied without checksum verification. " + summary : summary
            if record.verificationMode == .quick { record.state = .issues }
            record.endedAt = Date()
        }
    }

    func interrupt(id: UUID, summary: String, results: [ResultRow]? = nil) throws {
        try update(id: id) { record in
            guard record.state == .running else { throw LocalTransferJournalError.invalidState }
            record.state = .interrupted
            record.summary = summary
            if let results { record.results = results }
            record.endedAt = Date()
        }
    }

    func cancel(id: UUID, summary: String = "Cancelled", results: [ResultRow]? = nil) throws {
        try update(id: id) { record in
            guard record.state != .completed else { throw LocalTransferJournalError.invalidState }
            record.state = .cancelled
            record.summary = summary
            if let results { record.results = results }
            record.endedAt = Date()
        }
    }

    private func update(id: UUID, mutation: (inout LocalTransferRecord) throws -> Void) throws {
        var updated = records
        guard let index = updated.firstIndex(where: { $0.id == id }) else { throw LocalTransferJournalError.invalidState }
        try mutation(&updated[index])
        try commit(updated)
    }

    private func commit(_ updated: [LocalTransferRecord]) throws {
        guard !loadFailed else { throw LocalTransferJournalError.unreadableJournal(persistenceError ?? "Unknown error") }
        do {
            try persist(updated)
            records = updated
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            throw error
        }
    }

    private func persist(_ updated: [LocalTransferRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(updated).write(to: fileURL, options: .atomic)
    }
}
