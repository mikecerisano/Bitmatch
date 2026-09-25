import Foundation
@testable import BitMatch

/// The one `FileSystemService` test double. Tests configure it instead of
/// writing their own conformance.
///
/// Without a `backing` service it is inert: pickers return the scripted
/// results, access checks succeed, listings are empty, sizes are zero, and free
/// space is `freeSpaceResult`. With a `backing` service, access checks, listing,
/// sizing, directory creation, and free space forward to it; pickers still
/// return the scripted results so a test can never open a real panel.
///
/// Every `startAccessing`/`stopAccessing` pair is counted per path, so tests can
/// assert that scopes were balanced. Behavior that needs its own state (fault
/// injection, blocking, scope enforcement) belongs in a subclass that overrides
/// only the methods it changes.
class FakeFileSystemService: FileSystemService, @unchecked Sendable {
    let backing: FileSystemService?

    var sourceResult: URL?
    var destinationResults: [URL] = []
    var leftResult: URL?
    var rightResult: URL?
    var freeSpaceResult: Int64 = .max

    private let scopeLock = NSLock()
    private var activeScopes: [String: Int] = [:]

    init(backing: FileSystemService? = nil) {
        self.backing = backing
    }

    func selectSourceFolder() async -> URL? { sourceResult }
    func selectDestinationFolders() async -> [URL] { destinationResults }
    func selectLeftFolder() async -> URL? { leftResult }
    func selectRightFolder() async -> URL? { rightResult }

    func validateFileAccess(url: URL) async -> Bool {
        guard let backing else { return true }
        return await backing.validateFileAccess(url: url)
    }

    func startAccessing(url: URL) -> Bool {
        scopeLock.lock()
        activeScopes[url.path, default: 0] += 1
        scopeLock.unlock()
        return backing?.startAccessing(url: url) ?? true
    }

    func stopAccessing(url: URL) {
        scopeLock.lock()
        activeScopes[url.path, default: 0] = max(0, activeScopes[url.path, default: 0] - 1)
        scopeLock.unlock()
        backing?.stopAccessing(url: url)
    }

    func getFileList(from folderURL: URL) async throws -> [URL] {
        guard let backing else { return [] }
        return try await backing.getFileList(from: folderURL)
    }

    nonisolated func getFileSize(for url: URL) throws -> Int64 {
        guard let backing else { return 0 }
        return try backing.getFileSize(for: url)
    }

    nonisolated func createDirectory(at url: URL) throws {
        try backing?.createDirectory(at: url)
    }

    nonisolated func freeSpace(at url: URL) -> Int64 {
        guard let backing else { return freeSpaceResult }
        return backing.freeSpace(at: url)
    }

    /// Scopes opened on `url` and not yet closed.
    nonisolated func activeScopeCount(for url: URL) -> Int {
        scopeLock.lock()
        defer { scopeLock.unlock() }
        return activeScopes[url.path, default: 0]
    }

    /// Scopes still open on any path. Zero means every start had a stop.
    nonisolated var totalActiveScopes: Int {
        scopeLock.lock()
        defer { scopeLock.unlock() }
        return activeScopes.values.reduce(0, +)
    }
}
