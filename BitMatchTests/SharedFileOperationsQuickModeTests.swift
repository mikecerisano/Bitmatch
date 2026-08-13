// SharedFileOperationsQuickModeTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedFileOperationsQuickModeTests {

    @Test
    func testQuickModeSkipsVerification() async throws {
        try await FileOperationsTestLock.shared.run {
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
            #expect(op.results.allSatisfy { $0.success })
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

    @Test
    func testQuickModeDoesNotReuseExistingDestinationFile() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_quick_conflict_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_quick_conflict_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            let sourceFile = source.appendingPathComponent("clip.mov")
            try Data("same-size-source".utf8).write(to: sourceFile, options: .atomic)

            let settings = CameraLabelSettings()
            let outputRoot = SafetyValidator.resolvedDestinationRoot(source: source, destination: dest, settings: settings)
            try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
            let existingDestination = outputRoot.appendingPathComponent("clip.mov")
            try Data("same-size-target".utf8).write(to: existingDestination, options: .atomic)

            let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
            try fm.setAttributes([.modificationDate: sharedDate], ofItemAtPath: sourceFile.path)
            try fm.setAttributes([.modificationDate: sharedDate], ofItemAtPath: existingDestination.path)

            let sut = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: SharedChecksumService.shared
            )

            let op = try await sut.performFileOperation(
                sourceURL: source,
                destinationURLs: [dest],
                verificationMode: .quick,
                settings: settings,
                estimatedTotalBytes: nil,
                progressCallback: { _ in },
                onFileResult: { _ in }
            )

            let destinationContents = try String(contentsOf: existingDestination, encoding: .utf8)
            #expect(destinationContents == "same-size-target")
            #expect(op.results.contains { result in
                !result.success
                    && result.sourceURL.lastPathComponent == "clip.mov"
                    && result.error?.localizedDescription.contains("Quick mode cannot prove") == true
            })

            try? fm.removeItem(at: source)
            try? fm.removeItem(at: dest)
            #else
            #expect(true)
            #endif
        }
    }
}
