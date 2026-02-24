import Foundation
import Testing
@testable import BitMatch

struct SharedFileOperationsEdgeCaseTests {

    @Test
    func testCopySkipsSymlinkEntries() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_symlink_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_symlink_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            let realFile = source.appendingPathComponent("real.txt")
            try Data("real-data".utf8).write(to: realFile, options: .atomic)
            let symlink = source.appendingPathComponent("link.txt")
            try fm.createSymbolicLink(at: symlink, withDestinationURL: realFile)

            let settings = CameraLabelSettings()
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

            let expectedFolderName = settings.formattedFolderName(for: source.lastPathComponent)
            let expectedDestRoot = dest.appendingPathComponent(expectedFolderName)
            let copiedReal = op.results.first { $0.success && $0.sourceURL.lastPathComponent == "real.txt" }
            #expect(copiedReal != nil)
            if let copiedReal {
                #expect(copiedReal.destinationURL.path.hasPrefix(expectedDestRoot.path))
                #expect(fm.fileExists(atPath: copiedReal.destinationURL.path))
            }
            let copiedSymlink = op.results.contains { $0.sourceURL.lastPathComponent == "link.txt" && $0.success }
            #expect(copiedSymlink == false)
            #expect(fm.fileExists(atPath: expectedDestRoot.appendingPathComponent("link.txt").path) == false)

            try? fm.removeItem(at: source)
            try? fm.removeItem(at: dest)
            #else
            #expect(true)
            #endif
        }
    }

    @Test
    func testCopyPreservesSourceModificationDate() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_mtime_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_mtime_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            let sourceFile = source.appendingPathComponent("clip.mov")
            try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: sourceFile, options: .atomic)

            let expectedDate = Date(timeIntervalSince1970: 1_700_000_000)
            try fm.setAttributes([.modificationDate: expectedDate], ofItemAtPath: sourceFile.path)

            let settings = CameraLabelSettings()
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

            let expectedFolderName = settings.formattedFolderName(for: source.lastPathComponent)
            let expectedDestRoot = dest.appendingPathComponent(expectedFolderName)
            let copiedClip = op.results.first { $0.success && $0.sourceURL.lastPathComponent == "clip.mov" }
            #expect(copiedClip != nil)
            let destinationFile = try #require(copiedClip?.destinationURL)
            #expect(destinationFile.path.hasPrefix(expectedDestRoot.path))
            #expect(fm.fileExists(atPath: destinationFile.path))
            let dstModDate = try destinationFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            #expect(dstModDate != nil)
            if let dstModDate {
                #expect(abs(dstModDate.timeIntervalSince(expectedDate)) <= 2.0)
            }

            try? fm.removeItem(at: source)
            try? fm.removeItem(at: dest)
            #else
            #expect(true)
            #endif
        }
    }
}
