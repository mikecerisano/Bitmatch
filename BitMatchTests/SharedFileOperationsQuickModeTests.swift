// SharedFileOperationsQuickModeTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedFileOperationsQuickModeTests {

    @Test
    func testQuickModeSkipsVerification() async throws {
        #if os(macOS)
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let source = tmp.appendingPathComponent("bitmatch_quick_src_\(UUID().uuidString)")
        let dest = tmp.appendingPathComponent("bitmatch_quick_dst_\(UUID().uuidString)")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        // Small file tree
        try Data("q1".utf8).write(to: source.appendingPathComponent("q1.txt"))
        try Data("q2".utf8).write(to: source.appendingPathComponent("q2.txt"))

        let sut = SharedFileOperationsService(
            fileSystem: MacOSFileSystemService.shared,
            checksum: SharedChecksumService.shared
        )

        var final: OperationProgress?
        let op = try await sut.performFileOperation(
            sourceURL: source,
            destinationURLs: [dest],
            verificationMode: .quick,
            settings: CameraLabelSettings(),
            estimatedTotalBytes: nil,
            progressCallback: { prog in
                final = prog
            },
            onFileResult: { _ in }
        )

        #expect(final?.overallProgress == 1.0)
        #expect(op.results.count >= 2)
        // Quick mode should not attach verification results
        let anyVerification = op.results.contains { $0.verificationResult != nil }
        #expect(anyVerification == false)

        try? fm.removeItem(at: source)
        try? fm.removeItem(at: dest)
        #else
        #expect(true)
        #endif
    }
}
