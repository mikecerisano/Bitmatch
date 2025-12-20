// SharedFileOperationsParanoidTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedFileOperationsParanoidTests {

    @Test
    func testParanoidVerificationOnSmallFiles() async throws {
        #if os(macOS)
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let source = tmp.appendingPathComponent("bitmatch_paranoid_src_\(UUID().uuidString)")
        let dest = tmp.appendingPathComponent("bitmatch_paranoid_dst_\(UUID().uuidString)")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        // Create two tiny files (fast for byte-compare)
        try Data("alpha".utf8).write(to: source.appendingPathComponent("alpha.txt"))
        try Data("beta".utf8).write(to: source.appendingPathComponent("beta.txt"))

        let sut = SharedFileOperationsService(
            fileSystem: MacOSFileSystemService.shared,
            checksum: SharedChecksumService.shared
        )

        var finalProgress: OperationProgress?
        let op = try await sut.performFileOperation(
            sourceURL: source,
            destinationURLs: [dest],
            verificationMode: .paranoid,
            settings: CameraLabelSettings(),
            estimatedTotalBytes: nil,
            progressCallback: { prog in
                finalProgress = prog
            },
            onFileResult: { _ in }
        )

        // Assert: completed, verified results
        #expect(finalProgress?.overallProgress == 1.0)
        #expect(op.results.count >= 2)
        let verifiedCount = op.results.filter { $0.verificationResult?.isValid == true }.count
        #expect(verifiedCount >= 2)

        // Cleanup
        try? fm.removeItem(at: source)
        try? fm.removeItem(at: dest)
        #else
        #expect(true)
        #endif
    }
}
