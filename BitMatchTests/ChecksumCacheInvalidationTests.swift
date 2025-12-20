// ChecksumCacheInvalidationTests.swift
import Foundation
import Testing
@testable import BitMatch

struct ChecksumCacheInvalidationTests {

    @Test
    func testCacheInvalidatesWhenFileChanges() async throws {
        // Arrange
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let url = tmp.appendingPathComponent("bitmatch_cache_inval_\(UUID().uuidString).dat")

        // Write initial contents and compute checksum
        try Data("v1-contents".utf8).write(to: url, options: .atomic)
        let v1 = try await SharedChecksumService.shared.generateChecksum(for: url, type: .sha256, progressCallback: nil)
        let cachedV1 = await SharedChecksumCache.shared.get(for: url, algorithm: ChecksumAlgorithm.sha256.rawValue)
        #expect(cachedV1?.lowercased() == v1.lowercased())

        // Modify the file (different size and mod time)
        try Data("v2-changed-contents".utf8).write(to: url, options: .atomic)

        // Act: generate again, expecting a different checksum
        let v2 = try await SharedChecksumService.shared.generateChecksum(for: url, type: .sha256, progressCallback: nil)

        // Assert: checksum changed and cache now returns the new value
        #expect(v1.lowercased() != v2.lowercased())
        let cachedV2 = await SharedChecksumCache.shared.get(for: url, algorithm: ChecksumAlgorithm.sha256.rawValue)
        #expect(cachedV2?.lowercased() == v2.lowercased())

        // Cleanup
        try? fm.removeItem(at: url)
    }
}

