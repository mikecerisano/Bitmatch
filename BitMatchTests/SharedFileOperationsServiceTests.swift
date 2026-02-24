// SharedFileOperationsServiceTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedFileOperationsServiceTests {

    @Test
    func testCopyAndVerifySmallTree() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            // Arrange: create a temporary source folder with a couple of files
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let sourceRoot = tmp.appendingPathComponent("bitmatch_src_\(UUID().uuidString)")
            let destRoot = tmp.appendingPathComponent("bitmatch_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

            let fileA = sourceRoot.appendingPathComponent("A.txt")
            let fileB = sourceRoot.appendingPathComponent("B.bin")
            try Data("hello".utf8).write(to: fileA)
            try Data((0..<2048).map { _ in UInt8.random(in: 0...255) }).write(to: fileB)

            // Service under test
            let sut = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: SharedChecksumService.shared
            )

            var lastProgress = OperationProgress(
                overallProgress: 0,
                currentFile: nil,
                filesProcessed: 0,
                totalFiles: 0,
                currentStage: .idle,
                speed: nil,
                timeRemaining: nil
            )

            // Act: perform copy to a single destination
            let op = try await sut.performFileOperation(
                sourceURL: sourceRoot,
                destinationURLs: [destRoot],
                verificationMode: .standard,
                settings: CameraLabelSettings(),
                estimatedTotalBytes: nil,
                progressCallback: { prog in
                    lastProgress = prog
                },
                onFileResult: { _ in }
            )

            // Assert basic invariants
            #expect(op.results.count >= 2)
            #expect(lastProgress.totalFiles >= 2)
            #expect(lastProgress.overallProgress == 1.0)

            // Verify result mapping and destination existence using returned operation data
            let resultA = op.results.first { $0.success && $0.sourceURL.lastPathComponent == "A.txt" }
            let resultB = op.results.first { $0.success && $0.sourceURL.lastPathComponent == "B.bin" }
            #expect(resultA != nil)
            #expect(resultB != nil)
            if let resultA {
                #expect(resultA.destinationURL.path.hasPrefix(destRoot.path))
                #expect(fm.fileExists(atPath: resultA.destinationURL.path))
            }
            if let resultB {
                #expect(resultB.destinationURL.path.hasPrefix(destRoot.path))
                #expect(fm.fileExists(atPath: resultB.destinationURL.path))
            }

            // Cleanup
            try? fm.removeItem(at: sourceRoot)
            try? fm.removeItem(at: destRoot)
            #else
            // Skip on non-macOS test environments for now
            #expect(true)
            #endif
        }
    }
}
