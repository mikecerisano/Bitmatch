// SafetyValidatorTests.swift
import XCTest
@testable import BitMatch

final class SafetyValidatorTests: XCTestCase {

    func testAvailableSpaceFallsBackWhenImportantUsageCapacityIsUnavailable() {
        XCTAssertEqual(
            SafetyValidator.resolvedAvailableSpace(
                importantUsage: nil,
                standardCapacity: 2_000_000_000
            ),
            2_000_000_000
        )
        XCTAssertEqual(
            SafetyValidator.resolvedAvailableSpace(
                importantUsage: 1_500_000_000,
                standardCapacity: 2_000_000_000
            ),
            1_500_000_000
        )
    }

    // MARK: - System Directory Rejection

    func testRejectsSystemDirectories() {
        let systemPaths = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/var"]
        for path in systemPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertTrue(DropValidation.isSystemDirectory(url), "Should reject system path: \(path)")
        }
    }

    func testRejectsSystemSubdirectories() {
        let url = URL(fileURLWithPath: "/System/Library/Frameworks")
        XCTAssertTrue(DropValidation.isSystemDirectory(url))
    }

    func testAllowsUserDirectories() {
        let safePaths = ["/Users/test", "/Volumes/External", "/tmp/test"]
        for path in safePaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertFalse(DropValidation.isSystemDirectory(url), "Should allow path: \(path)")
        }
    }

    // MARK: - Path Traversal

    func testRejectsPathTraversal() {
        let maliciousPaths = [
            "/Users/test/../../../etc/passwd",
            "/Volumes/Card/../System",
            "/tmp/safe/../../private"
        ]
        for path in maliciousPaths {
            let url = URL(fileURLWithPath: path)
            let resolved = url.standardized
            // After resolution, check if it lands in a system directory
            XCTAssertTrue(
                DropValidation.isSystemDirectory(resolved) || resolved.pathComponents.contains("..") == false,
                "Path traversal should be caught: \(path)"
            )
        }
    }

    // MARK: - Directory Validation

    func testDirectoriesOnlyRejectsFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("test.txt")
        try Data("test".utf8).write(to: file)

        XCTAssertFalse(DropValidation.directoriesOnly([file]))
        XCTAssertTrue(DropValidation.directoriesOnly([tempDir]))
    }

    func testDirectoriesOnlyRejectsSystemDirs() {
        let url = URL(fileURLWithPath: "/System")
        XCTAssertFalse(DropValidation.directoriesOnly([url]))
    }

    // MARK: - Symlink Handling

    func testSymlinkResolution() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let target = tempDir.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let link = tempDir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        // Symlink to safe directory should be allowed
        let resolved = link.resolvingSymlinksInPath()
        XCTAssertFalse(DropValidation.isSystemDirectory(resolved))
    }

    // MARK: - Validation Combinators

    func testSingleItemValidation() {
        let url1 = URL(fileURLWithPath: "/tmp/a")
        let url2 = URL(fileURLWithPath: "/tmp/b")
        XCTAssertTrue(DropValidation.singleItem([url1]))
        XCTAssertFalse(DropValidation.singleItem([url1, url2]))
    }

    func testMultipleItemsValidation() {
        let url1 = URL(fileURLWithPath: "/tmp/a")
        let url2 = URL(fileURLWithPath: "/tmp/b")
        XCTAssertFalse(DropValidation.multipleItems([url1]))
        XCTAssertTrue(DropValidation.multipleItems([url1, url2]))
    }

    func testCombinedValidators() {
        let combined = DropValidation.combine([
            DropValidation.singleItem,
            DropValidation.directoriesOnly
        ])

        let url = URL(fileURLWithPath: "/tmp")
        // /tmp is a directory and single item
        XCTAssertTrue(combined([url]))
    }

    // MARK: - Empty Input

    func testEmptyURLArray() {
        XCTAssertFalse(DropValidation.directoriesOnly([]))
        // singleItem and multipleItems with empty should return false
        XCTAssertFalse(DropValidation.singleItem([]))
        XCTAssertFalse(DropValidation.multipleItems([]))
    }

    // MARK: - Transfer Safety

    func testSafetyChecksRejectDestinationInsideSource() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let destination = source.appendingPathComponent("Backup")

        await assertThrowsFileOperationError(expectedMessage: "Destination is inside the source folder") {
            try await SafetyValidator.performSafetyChecks(
                source: source,
                destinations: [destination],
                sourceSizeBytes: 0
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSafetyChecksRejectDestinationContainingSource() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        await assertThrowsFileOperationError(expectedMessage: "Destination contains the source folder") {
            try await SafetyValidator.performSafetyChecks(
                source: source,
                destinations: [root],
                sourceSizeBytes: 0
            )
        }
    }

    func testSafetyChecksRejectDuplicateDestinations() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Source")
        let destination = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        await assertThrowsFileOperationError(expectedMessage: "Destination folders must be unique") {
            try await SafetyValidator.performSafetyChecks(
                source: source,
                destinations: [destination, destination],
                sourceSizeBytes: 0
            )
        }
    }

    func testSafetyChecksUseSuppliedSourceSizeInsteadOfEnumeratingBytes() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Source")
        let destination = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("tiny".utf8).write(to: source.appendingPathComponent("tiny.txt"))

        let suppliedSourceBytes: Int64 = 1_000_000_000_000_000
        do {
            try await SafetyValidator.performSafetyChecks(
                source: source,
                destinations: [destination],
                sourceSizeBytes: suppliedSourceBytes
            )
            XCTFail("Expected supplied source size to exceed available space")
        } catch FileOperationError.insufficientSpace(_, _, let requiredGB) {
            XCTAssertGreaterThan(requiredGB, Double(suppliedSourceBytes) / 1_000_000_000)
        } catch {
            XCTFail("Expected FileOperationError.insufficientSpace, got \(error)")
        }
    }

    func testSafetyChecksHeadroomOverflowThrowsTypedError() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Source")
        let destination = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        await assertThrowsFileOperationError(expectedMessage: "Source size exceeds the supported range") {
            try await SafetyValidator.performSafetyChecks(
                source: source,
                destinations: [destination],
                sourceSizeBytes: .max
            )
        }
    }

    func testPortableRelativePathValidationRejectsCaseOnlyCollisions() {
        XCTAssertThrowsError(try SafetyValidator.validatePortableRelativePaths([
            "A001/clip.mov",
            "a001/CLIP.mov"
        ])) { error in
            guard case FileOperationError.unsafeOperation(let message) = error else {
                return XCTFail("Expected unsafeOperation, got \(error)")
            }
            XCTAssertTrue(message.contains("collide on case-insensitive filesystems"))
        }
    }

    func testPortableRelativePathValidationRejectsUnsafeComponents() {
        XCTAssertThrowsError(try SafetyValidator.validatePortableRelativePaths([
            "A001/../clip.mov"
        ])) { error in
            guard case FileOperationError.unsafeOperation(let message) = error else {
                return XCTFail("Expected unsafeOperation, got \(error)")
            }
            XCTAssertTrue(message.contains("unsafe relative path"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assertThrowsFileOperationError(
        expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected FileOperationError.unsafeOperation", file: file, line: line)
        } catch FileOperationError.unsafeOperation(let message) {
            XCTAssertEqual(message, expectedMessage, file: file, line: line)
        } catch {
            XCTFail("Expected FileOperationError.unsafeOperation, got \(error)", file: file, line: line)
        }
    }
}
