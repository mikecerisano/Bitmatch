import Foundation
import Testing
@testable import BitMatch

struct SharedChecksumEdgeCaseTests {

    @Test
    func testGenerateChecksumForMissingFileThrowsNotFound() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch_missing_\(UUID().uuidString).bin")

        do {
            _ = try await SharedChecksumService.shared.generateChecksum(
                for: missing,
                type: .sha256,
                progressCallback: nil
            )
            Issue.record("Expected file-not-found error")
        } catch let error as BitMatchError {
            switch error {
            case .fileNotFound(let url):
                #expect(url.path == missing.path)
            default:
                Issue.record("Expected .fileNotFound, got \(error.localizedDescription)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func testSHA256ForEmptyFileMatchesKnownDigest() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let fileURL = tmp.appendingPathComponent("bitmatch_empty_\(UUID().uuidString).dat")
        try Data().write(to: fileURL, options: .atomic)

        let checksum = try await SharedChecksumService.shared.generateChecksum(
            for: fileURL,
            type: .sha256,
            progressCallback: nil
        )
        #expect(checksum.lowercased() == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

        try? fm.removeItem(at: fileURL)
    }

    @Test
    func testByteComparisonReturnsFalseForDifferentSizes() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let a = tmp.appendingPathComponent("bitmatch_size_a_\(UUID().uuidString).bin")
        let b = tmp.appendingPathComponent("bitmatch_size_b_\(UUID().uuidString).bin")

        try Data("12345".utf8).write(to: a, options: .atomic)
        try Data("123456".utf8).write(to: b, options: .atomic)

        let matches = try await SharedChecksumService.shared.performByteComparison(
            sourceURL: a,
            destinationURL: b,
            progressCallback: nil
        )
        #expect(matches == false)

        try? fm.removeItem(at: a)
        try? fm.removeItem(at: b)
    }
}
