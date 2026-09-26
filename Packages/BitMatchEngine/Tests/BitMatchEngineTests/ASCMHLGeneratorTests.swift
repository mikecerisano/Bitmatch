import CryptoKit
import Foundation
import XCTest
@testable import BitMatchEngine

final class ASCMHLGeneratorTests: XCTestCase {
    func testC4MatchesOfficialReferenceEmptyDataVector() {
        XCTAssertEqual(ASCMHLGenerator.c4(Data()), "c459dsjfscH38cYeXXYogktxf4Cd9ibshE3BHUo6a58hBXmRQdZrAkZzsWcbWtDg5oQstpDuni4Hirj75GEmTc1sFT")
    }

    func testEmptyInventoryDoesNotPublishHistory() throws {
        let (root, _) = try fixture()
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [], startTime: Date(), toolVersion: "test"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ascmhl").path))
    }

    func testSourceOverlapAndAncestorSymlinkCannotPublish() throws {
        let (root, file) = try fixture()
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for source in [root, root.deletingLastPathComponent(), nested] {
            XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [file], startTime: Date(), sourceURL: source, toolVersion: "test")) { error in
                guard case ASCMHLGenerator.GenerationError.sourceOverlap = error else {
                    return XCTFail("Expected source overlap, got \(error)")
                }
            }
        }
        let alias = root.deletingLastPathComponent().appendingPathComponent("ascmhl-alias-\(UUID())")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: alias.appendingPathComponent("nested"), files: [file], startTime: Date(), sourceURL: root, toolVersion: "test")) { error in
            guard case ASCMHLGenerator.GenerationError.sourceOverlap = error else {
                return XCTFail("Expected source overlap through alias, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ascmhl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.appendingPathComponent("ascmhl").path))
    }

    private func fixture() throws -> (URL, ASCMHLGenerator.VerifiedFile) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ascmhl-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let data = Data("verified media".utf8)
        try data.write(to: root.appendingPathComponent("clip.txt"))
        return (root, .init(relativePath: "clip.txt", size: Int64(data.count), expectedSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
    }

    func testChangedDestinationDoesNotPublishHistory() throws {
        let (root, file) = try fixture()
        try Data("corrupt media!".utf8).write(to: root.appendingPathComponent("clip.txt"))
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [file], startTime: Date(), toolVersion: "test"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ascmhl").path))
    }

    func testExistingHistoryIsByteForBytePreserved() throws {
        let (root, file) = try fixture()
        let manifest = try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [file], startTime: Date(), toolVersion: "test")
        let chain = manifest.deletingLastPathComponent().appendingPathComponent("ascmhl_chain.xml")
        let original = try Data(contentsOf: manifest)
        let originalChain = try Data(contentsOf: chain)
        XCTAssertTrue(String(decoding: original, as: UTF8.self).contains(#"<tool version="test">BitMatch</tool>"#),
                      "the manifest names the app version it was given")
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [file], startTime: Date(), toolVersion: "test"))
        XCTAssertEqual(try Data(contentsOf: manifest), original)
        XCTAssertEqual(try Data(contentsOf: chain), originalChain)
    }

    func testNestedHistoryAndUnsafePathsAreRejected() throws {
        let (root, file) = try fixture()
        for path in ["../clip.txt", "/clip.txt", "a/../clip.txt", "ascmhl/clip.txt", "a\\clip.txt"] {
            XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [.init(relativePath: path, size: file.size, expectedSHA256: file.expectedSHA256)], startTime: Date(), toolVersion: "test"))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested/ascmhl"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [file], startTime: Date(), toolVersion: "test"))
    }

    func testSymlinkAndDuplicatePathsAreRejected() throws {
        let (root, file) = try fixture()
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [file, file], startTime: Date(), toolVersion: "test"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias.txt").path, withDestinationPath: "clip.txt")
        XCTAssertThrowsError(try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: [.init(relativePath: "alias.txt", size: file.size, expectedSHA256: file.expectedSHA256)], startTime: Date(), toolVersion: "test"))
    }
}
