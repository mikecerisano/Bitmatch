import Foundation
import XCTest
@testable import BitMatch

final class MHLGeneratorTests: XCTestCase {
    func testGenerateMHLRejectsEntriesOutsideDestination() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("bitmatch_mhl_\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("dest-a")
        let otherDestination = root.appendingPathComponent("dest-b")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.createDirectory(at: otherDestination, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let inside = destination.appendingPathComponent("clip-a.mov")
        let outside = otherDestination.appendingPathComponent("clip-b.mov")
        try Data("a".utf8).write(to: inside)
        try Data("b".utf8).write(to: outside)

        XCTAssertThrowsError(
            try MHLGenerator.generateMHL(
                for: [
                    (url: inside, hash: "aaa", size: 1),
                    (url: outside, hash: "bbb", size: 1)
                ],
                sourceURL: source,
                destinationURL: destination,
                algorithm: .sha256,
                jobID: UUID(),
                startTime: Date()
            )
        )
    }
}
