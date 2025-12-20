// ChecksumCacheTests.swift
import Foundation
import Testing
@testable import BitMatch

struct ChecksumCacheTests {

    @Test
    func testChecksumIsCachedAfterFirstGeneration() async throws {
        // Arrange
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let url = tmp.appendingPathComponent("bitmatch_cache_\(UUID().uuidString).dat")
        let data = Data("cache-me".utf8)
        try data.write(to: url, options: .atomic)

        // Act
        let first = try await SharedChecksumService.shared.generateChecksum(for: url, type: .sha256, progressCallback: nil)
        // Now, the cache should contain the value
        let cached = await SharedChecksumCache.shared.get(for: url, algorithm: ChecksumAlgorithm.sha256.rawValue)
        
        // Assert cache has entry and second call returns same checksum
        #expect(cached?.lowercased() == first.lowercased())
        let second = try await SharedChecksumService.shared.generateChecksum(for: url, type: .sha256, progressCallback: nil)
        #expect(second.lowercased() == first.lowercased())

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }
}

