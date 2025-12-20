// SharedChecksumByteCompareTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedChecksumByteCompareTests {

    @Test
    func testByteCompareMatchesForIdenticalFiles() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let a = tmp.appendingPathComponent("bitmatch_byte_a_\(UUID().uuidString).bin")
        let b = tmp.appendingPathComponent("bitmatch_byte_b_\(UUID().uuidString).bin")

        // Write identical contents
        let payload = Data((0..<8192).map { _ in UInt8.random(in: 0...255) })
        try payload.write(to: a, options: .atomic)
        try payload.write(to: b, options: .atomic)

        let matches = try await SharedChecksumService.shared.performByteComparison(
            sourceURL: a,
            destinationURL: b,
            progressCallback: nil
        )
        #expect(matches == true)

        try? fm.removeItem(at: a)
        try? fm.removeItem(at: b)
    }

    @Test
    func testByteCompareDetectsDifference() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let a = tmp.appendingPathComponent("bitmatch_byte_a_\(UUID().uuidString).bin")
        let b = tmp.appendingPathComponent("bitmatch_byte_b_\(UUID().uuidString).bin")

        // Same size, but one byte differs
        var payload = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
        try payload.write(to: a, options: .atomic)
        if !payload.isEmpty { payload[0] = payload[0] ^ 0xFF }
        try payload.write(to: b, options: .atomic)

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

