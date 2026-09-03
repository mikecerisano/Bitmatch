import XCTest
@testable import BitMatch

final class FileTreeEnumeratorTests: XCTestCase {
    func testMissingRootThrowsInsteadOfReturningEmptyManifest() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-manifest-\(UUID().uuidString)")
        XCTAssertThrowsError(try FileTreeEnumerator.enumerateRegularFiles(base: missing))
    }

    func testValidEmptyRootReturnsEmptyManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(try FileTreeEnumerator.enumerateRegularFiles(base: root).isEmpty)
    }

    func testPreCancelledTaskThrowsForValidEmptyRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancelled-empty-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FileTreeEnumerator.enumerateRegularFiles(base: root)
        }

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// Cards carry macOS volume metadata folders (.Spotlight-V100, .fseventsd, ...) that are
    /// unreadable without Full Disk Access. They are never user data and must be skipped,
    /// not treated as a fatal traversal error.
    func testSkipsUnreadableVolumeMetadataDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("metadata-manifest-\(UUID().uuidString)", isDirectory: true)
        let spotlight = root.appendingPathComponent(".Spotlight-V100", isDirectory: true)
        let dcim = root.appendingPathComponent("DCIM", isDirectory: true)
        try fm.createDirectory(at: spotlight, withIntermediateDirectories: true)
        try fm.createDirectory(at: dcim, withIntermediateDirectories: true)
        try Data("clip".utf8).write(to: dcim.appendingPathComponent("A001.MOV"))
        try Data("index".utf8).write(to: spotlight.appendingPathComponent("store.db"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: spotlight.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: spotlight.path)
            try? fm.removeItem(at: root)
        }

        let entries = try FileTreeEnumerator.enumerateRegularFiles(base: root)
        // Compare trailing components: the enumerator may return /private/var for a /var temp root.
        XCTAssertEqual(entries.map { $0.url.pathComponents.suffix(2).joined(separator: "/") }, ["DCIM/A001.MOV"])
    }

    /// An unreadable directory that is NOT known volume metadata must still fail loudly.
    func testUnreadableUserDirectoryStillThrows() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("unreadable-manifest-\(UUID().uuidString)", isDirectory: true)
        let locked = root.appendingPathComponent("PRIVATE", isDirectory: true)
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? fm.removeItem(at: root)
        }

        XCTAssertThrowsError(try FileTreeEnumerator.enumerateRegularFiles(base: root))
    }
}
