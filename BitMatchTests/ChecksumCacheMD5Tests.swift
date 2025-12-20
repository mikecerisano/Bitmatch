// ChecksumCacheMD5Tests.swift
import Foundation
import Testing
@testable import BitMatch

struct ChecksumCacheMD5Tests {

    @Test
    func testMD5IsCachedAfterFirstGeneration() async throws {
        // Arrange
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let url = tmp.appendingPathComponent("bitmatch_cache_md5_\(UUID().uuidString).dat")
        let data = Data("md5-cache".utf8)
        try data.write(to: url, options: .atomic)

        // Act
        let first = try await SharedChecksumService.shared.generateChecksum(for: url, type: .md5, progressCallback: nil)
        // Cache should contain this value keyed by file metadata
        let cached = await SharedChecksumCache.shared.get(for: url, algorithm: ChecksumAlgorithm.md5.rawValue)

        // Assert cache has entry and second call returns same checksum
        #expect(cached?.lowercased() == first.lowercased())
        let second = try await SharedChecksumService.shared.generateChecksum(for: url, type: .md5, progressCallback: nil)
        #expect(second.lowercased() == first.lowercased())

        // Cleanup
        try? fm.removeItem(at: url)
    }
}

