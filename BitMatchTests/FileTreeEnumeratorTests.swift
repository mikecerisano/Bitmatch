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
}
