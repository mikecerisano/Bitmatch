import Foundation
import Testing
@testable import BitMatch

struct SharedFileOperationsEdgeCaseTests {

    @Test
    func testEstimatedSizeHeadroomOverflowThrowsTypedError() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_overflow_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_overflow_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            defer {
                try? fm.removeItem(at: source)
                try? fm.removeItem(at: dest)
            }

            let sut = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: SharedChecksumService.shared
            )

            do {
                _ = try await sut.performFileOperation(
                    sourceURL: source,
                    destinationURLs: [dest],
                    verificationMode: .quick,
                    settings: CameraLabelSettings(),
                    estimatedTotalBytes: .max,
                    progressCallback: { _ in },
                    onFileResult: nil
                )
                Issue.record("Expected typed source-size overflow error")
            } catch FileOperationError.unsafeOperation(let message) {
                #expect(message == "Source size exceeds the supported range")
            } catch {
                Issue.record("Expected FileOperationError.unsafeOperation, got \(error)")
            }
            #else
            #expect(true)
            #endif
        }
    }

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

    @Test
    func testCopyDoesNotOverwriteExistingConflictingDestinationFile() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_conflict_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_conflict_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            try Data("source-version".utf8).write(to: source.appendingPathComponent("clip.txt"), options: .atomic)

            let settings = CameraLabelSettings()
            let outputRoot = SafetyValidator.resolvedDestinationRoot(source: source, destination: dest, settings: settings)
            try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
            let existingDestination = outputRoot.appendingPathComponent("clip.txt")
            try Data("do-not-overwrite".utf8).write(to: existingDestination, options: .atomic)

            let sut = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: SharedChecksumService.shared
            )

            let op = try await sut.performFileOperation(
                sourceURL: source,
                destinationURLs: [dest],
                verificationMode: .standard,
                settings: settings,
                estimatedTotalBytes: nil,
                progressCallback: { _ in },
                onFileResult: { _ in }
            )

            let destinationContents = try String(contentsOf: existingDestination, encoding: .utf8)
            #expect(destinationContents == "do-not-overwrite")
            #expect(op.results.contains { !$0.success && $0.sourceURL.lastPathComponent == "clip.txt" })

            try? fm.removeItem(at: source)
            try? fm.removeItem(at: dest)
            #else
            #expect(true)
            #endif
        }
    }

    @Test
    func testCopyIncludesHiddenFilesAndEmptyDirectories() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_hidden_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_hidden_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            try Data("hidden-sidecar".utf8).write(to: source.appendingPathComponent(".metadata"), options: .atomic)
            try fm.createDirectory(at: source.appendingPathComponent("EMPTY_DIR"), withIntermediateDirectories: true)

            let settings = CameraLabelSettings()
            let sut = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: SharedChecksumService.shared
            )

            _ = try await sut.performFileOperation(
                sourceURL: source,
                destinationURLs: [dest],
                verificationMode: .quick,
                settings: settings,
                estimatedTotalBytes: nil,
                progressCallback: { _ in },
                onFileResult: { _ in }
            )

            let outputRoot = SafetyValidator.resolvedDestinationRoot(source: source, destination: dest, settings: settings)
            #expect(fm.fileExists(atPath: outputRoot.appendingPathComponent(".metadata").path))

            var isDirectory: ObjCBool = false
            let emptyDirExists = fm.fileExists(
                atPath: outputRoot.appendingPathComponent("EMPTY_DIR").path,
                isDirectory: &isDirectory
            )
            #expect(emptyDirExists && isDirectory.boolValue)

            try? fm.removeItem(at: source)
            try? fm.removeItem(at: dest)
            #else
            #expect(true)
            #endif
        }
    }

    @Test
    func testPinnedDestinationKeepsDescendantCreationAndPublishOutOfSwappedSymlink() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let temporaryRoot = fm.temporaryDirectory
                .appendingPathComponent("bitmatch_pinned_destination_\(UUID().uuidString)")
            let source = temporaryRoot.appendingPathComponent("Source")
            let destination = temporaryRoot.appendingPathComponent("Destination")
            let originalJob = destination.appendingPathComponent("Job")
            let heldJob = destination.appendingPathComponent("Job-held")
            let escape = temporaryRoot.appendingPathComponent("Escape")
            try fm.createDirectory(at: source.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try fm.createDirectory(at: escape, withIntermediateDirectories: true)
            try Data("pinned contents".utf8).write(to: source.appendingPathComponent("DCIM/clip.txt"))
            defer { try? fm.removeItem(at: temporaryRoot) }

            let pinnedRoot = try PinnedDestinationDirectory.open(
                destination: destination,
                rootComponents: ["Job", "Card-001"]
            )
            try fm.moveItem(at: originalJob, to: heldJob)
            try fm.createSymbolicLink(at: originalJob, withDestinationURL: escape)

            try await FileCopyService.copyAllSafely(
                from: source,
                toPinnedRoot: pinnedRoot,
                verificationMode: .quick,
                workers: 1,
                onProgress: { _, _ in },
                onError: { _, error in
                    Issue.record("Pinned copy unexpectedly failed: \(error.localizedDescription)")
                }
            )

            #expect(fm.fileExists(atPath: heldJob.appendingPathComponent("Card-001/DCIM/clip.txt").path))
            #expect(!fm.fileExists(atPath: escape.appendingPathComponent("Card-001/DCIM/clip.txt").path))
            #else
            #expect(true)
            #endif
        }
    }

    @Test
    func testSourceMutationDuringCopyDoesNotPublishDestinationFile() async throws {
        try await FileOperationsTestLock.shared.run {
            #if os(macOS)
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory
            let source = tmp.appendingPathComponent("bitmatch_mutation_src_\(UUID().uuidString)")
            let dest = tmp.appendingPathComponent("bitmatch_mutation_dst_\(UUID().uuidString)")
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            let sourceFile = source.appendingPathComponent("large.bin")
            try Data(repeating: 0x41, count: 6 * 1024 * 1024).write(to: sourceFile, options: .atomic)

            let mutator = SourceMutationTrigger(sourceFile: sourceFile)
            let errors = AsyncErrorCollector()

            try await FileCopyService.copyAllSafely(
                from: source,
                toRoot: dest,
                verificationMode: .quick,
                workers: 1,
                pauseCheck: {
                    try await mutator.tick()
                },
                onProgress: { _, _ in },
                onError: { _, error in
                    await errors.append(error.localizedDescription)
                }
            )

            let capturedErrors = await errors.messages
            #expect(capturedErrors.contains { $0.contains("Source file changed during copy") })
            #expect(!fm.fileExists(atPath: dest.appendingPathComponent("large.bin").path))

            try? fm.removeItem(at: source)
            try? fm.removeItem(at: dest)
            #else
            #expect(true)
            #endif
        }
    }

    @Test
    func testResultStoreRetainsLargeResultSetAndUpserts() async throws {
        let store = ResultStore()
        let baseSource = URL(fileURLWithPath: "/tmp/bitmatch-result-store-source")
        let baseDest = URL(fileURLWithPath: "/tmp/bitmatch-result-store-dest")

        for index in 0..<12_000 {
            let result = FileOperationResult(
                sourceURL: baseSource.appendingPathComponent("file-\(index).mov"),
                destinationURL: baseDest.appendingPathComponent("file-\(index).mov"),
                success: true,
                error: nil,
                fileSize: Int64(index),
                verificationResult: nil,
                processingTime: 0
            )
            await store.upsert(result)
        }

        let updated = FileOperationResult(
            sourceURL: baseSource.appendingPathComponent("file-42.mov"),
            destinationURL: baseDest.appendingPathComponent("file-42.mov"),
            success: false,
            error: NSError(domain: "BitMatchTests", code: 42),
            fileSize: 42,
            verificationResult: nil,
            processingTime: 0
        )
        await store.upsert(updated)

        let snapshot = await store.snapshot()
        #expect(snapshot.count == 12_000)
        #expect(snapshot.filter { $0.sourceURL.lastPathComponent == "file-42.mov" }.count == 1)
        #expect(snapshot.first { $0.sourceURL.lastPathComponent == "file-42.mov" }?.success == false)
    }

    @Test
    func testOverflowResultsCoalesceSpilledCopyRowsWithLatestVerifyRows() async throws {
        let service = ResultsOverflowService(operationId: UUID(), maxInMemoryResults: 1)
        let firstCopy = ResultRow(
            path: "/source/file-1.mov",
            status: "✅ Copied",
            size: 10,
            checksum: nil,
            destination: "RAID",
            destinationPath: "/dest/file-1.mov"
        )
        let secondCopy = ResultRow(
            path: "/source/file-2.mov",
            status: "✅ Copied",
            size: 20,
            checksum: nil,
            destination: "RAID",
            destinationPath: "/dest/file-2.mov"
        )
        let firstVerified = ResultRow(
            path: "/source/file-1.mov",
            status: "✅ Verified",
            size: 10,
            checksum: "abc123",
            destination: "RAID",
            destinationPath: "/dest/file-1.mov"
        )

        await service.addResult(firstCopy)
        await service.addResult(secondCopy)
        let updatedInMemory = await service.updateResult(
            matching: firstCopy.path,
            destination: firstCopy.destination ?? "",
            with: firstVerified
        )
        #expect(updatedInMemory == false)
        await service.addResult(firstVerified)

        let results = await service.getAllResults()
        #expect(results.count == 2)
        #expect(results.first { $0.path == firstCopy.path }?.status == "✅ Verified")
        #expect(results.first { $0.path == firstCopy.path }?.checksum == "abc123")
        await service.clear()
    }
}

private actor SourceMutationTrigger {
    private let sourceFile: URL
    private var tickCount = 0

    init(sourceFile: URL) {
        self.sourceFile = sourceFile
    }

    func tick() async throws {
        tickCount += 1
        if tickCount == 2 {
            try Data("changed".utf8).write(to: sourceFile, options: .atomic)
        }
    }
}

private actor AsyncErrorCollector {
    private(set) var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
    }
}
