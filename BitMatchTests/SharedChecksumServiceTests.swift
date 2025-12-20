// SharedChecksumServiceTests.swift
import Foundation
import CryptoKit
import Testing
@testable import BitMatch

struct SharedChecksumServiceTests {

    @Test
    func testSHA256MatchesCryptoKit() async throws {
        // Arrange: write a temporary file with known contents
        let tmp = FileManager.default.temporaryDirectory
        let fileURL = tmp.appendingPathComponent("bitmatch_test_sha256_\(UUID().uuidString).bin")
        let data = Data("BitMatch Test Payload".utf8)
        try data.write(to: fileURL, options: .atomic)

        // Act: compute via SharedChecksumService and CryptoKit
        let serviceChecksum = try await SharedChecksumService.shared.generateChecksum(
            for: fileURL,
            type: .sha256,
            progressCallback: nil
        )
        let cryptoDigest = SHA256.hash(data: data)
        let cryptoChecksum = cryptoDigest.map { String(format: "%02hhx", $0) }.joined()

        // Assert
        #expect(serviceChecksum.lowercased() == cryptoChecksum.lowercased())
        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test
    func testMD5MatchesCryptoKit() async throws {
        // Arrange
        let tmp = FileManager.default.temporaryDirectory
        let fileURL = tmp.appendingPathComponent("bitmatch_test_md5_\(UUID().uuidString).bin")
        let data = Data((0..<1024).map { _ in UInt8.random(in: 0...255) })
        try data.write(to: fileURL, options: .atomic)

        // Act
        let serviceChecksum = try await SharedChecksumService.shared.generateChecksum(
            for: fileURL,
            type: .md5,
            progressCallback: nil
        )
        let cryptoDigest = Insecure.MD5.hash(data: data)
        let cryptoChecksum = cryptoDigest.map { String(format: "%02hhx", $0) }.joined()

        // Assert
        #expect(serviceChecksum.lowercased() == cryptoChecksum.lowercased())
        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }
}

