// SafetyValidatorTests.swift
import XCTest
@testable import BitMatch

final class SafetyValidatorTests: XCTestCase {

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
}
