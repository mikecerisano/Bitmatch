// SharedCompareFlowTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedCompareFlowTests {

    @Test
    func testCleanCompareDoesNotInheritPriorCopyFailures() async throws {
        #if os(macOS)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("bitmatch_clean_compare_\(UUID().uuidString)")
        let left = root.appendingPathComponent("left")
        let right = root.appendingPathComponent("right")
        try fileManager.createDirectory(at: left, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let contents = Data("matching".utf8)
        try contents.write(to: left.appendingPathComponent("clip.mov"))
        try contents.write(to: right.appendingPathComponent("clip.mov"))

        let coordinator = await MainActor.run {
            SharedAppCoordinator(platformManager: MacOSPlatformManager.shared)
        }
        await MainActor.run {
            coordinator.results = [
                ResultRow(
                    path: "/previous/failed.mov",
                    status: "Checksum mismatch",
                    size: 8,
                    checksum: nil,
                    destination: "Previous destination"
                )
            ]
            coordinator.errorService.reportWarning(
                "Previous operation warning",
                context: .general(operation: "Copy", stage: "Verification")
            )
            coordinator.currentMode = .compareFolders
            coordinator.verificationMode = .standard
            coordinator.leftURL = left
            coordinator.rightURL = right
        }

        await coordinator.compareFolders()

        let outcome = await MainActor.run {
            let hasErrors = coordinator.hasErrors
            return (
                coordinator.results,
                hasErrors,
                CompletionVerdict.resolve(
                    state: coordinator.operationState,
                    rows: coordinator.results,
                    hasErrors: hasErrors,
                    hasCriticalErrors: coordinator.hasCriticalErrors
                )
            )
        }
        #expect(outcome.0.isEmpty)
        #expect(!outcome.1)
        #expect(outcome.2 == .success)
        #else
        #expect(true)
        #endif
    }

    @Test
    func testCompareFoldersCompletes() async throws {
        #if os(macOS)
        // Arrange: create two small folders with overlapping and unique files
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let left = tmp.appendingPathComponent("bitmatch_cmp_left_\(UUID().uuidString)")
        let right = tmp.appendingPathComponent("bitmatch_cmp_right_\(UUID().uuidString)")
        try fm.createDirectory(at: left, withIntermediateDirectories: true)
        try fm.createDirectory(at: right, withIntermediateDirectories: true)

        // Files: A in both (different contents), B only left, C only right
        try Data("A".utf8).write(to: left.appendingPathComponent("A.txt"))
        try Data("B".utf8).write(to: left.appendingPathComponent("B.txt"))
        try Data("X".utf8).write(to: right.appendingPathComponent("A.txt"))
        try Data("C".utf8).write(to: right.appendingPathComponent("C.txt"))

        // Act: drive compare via SharedAppCoordinator
        let coordinator = await MainActor.run { SharedAppCoordinator(platformManager: MacOSPlatformManager.shared) }
        await MainActor.run {
            coordinator.currentMode = .compareFolders
            coordinator.verificationMode = .standard
            coordinator.leftURL = left
            coordinator.rightURL = right
        }
        await coordinator.compareFolders()

        // Assert: operation completes successfully
        let statsAndState = await MainActor.run { () -> (CompareStats?, Bool) in
            let completed: Bool
            if case .completed = coordinator.operationState { completed = true } else { completed = false }
            return (coordinator.lastCompareStats, completed)
        }
        #expect(statsAndState.1)
        // Validate counts: common=0, onlyLeft=1 (B), onlyRight=1 (C), mismatched=1 (A)
        #expect(statsAndState.0?.commonCount == 0)
        #expect(statsAndState.0?.onlyInLeftCount == 1)
        #expect(statsAndState.0?.onlyInRightCount == 1)
        #expect(statsAndState.0?.mismatchedCount == 1)

        // Cleanup
        try? fm.removeItem(at: left)
        try? fm.removeItem(at: right)
        #else
        #expect(true)
        #endif
    }

    @Test
    func testCompareKeepsFolderScopesOpenThroughVerification() async throws {
        let left = URL(fileURLWithPath: "/scoped/left")
        let right = URL(fileURLWithPath: "/scoped/right")
        let fileSystem = ScopeTrackingFileSystem(left: left, right: right)
        let platform = ScopeTrackingPlatformManager(fileSystem: fileSystem)
        let coordinator = await MainActor.run { ComparisonCoordinator(platformManager: platform) }

        let stats = try await coordinator.compareFolders(
            left: left,
            right: right,
            verificationMode: .quick,
            onProgress: { _ in }
        )

        #expect(stats.commonCount == 1)
        #expect(fileSystem.didReadSizesWhileScoped)
        #expect(fileSystem.activeScopeCount(for: left) == 0)
        #expect(fileSystem.activeScopeCount(for: right) == 0)
    }
}

private enum ScopeTrackingError: Error {
    case missingScope(String)
}

private final class ScopeTrackingFileSystem: FileSystemService {
    private let left: URL
    private let right: URL
    private let leftFile: URL
    private let rightFile: URL
    private let lock = NSLock()
    private var activeScopes: [String: Int] = [:]
    private(set) var didReadSizesWhileScoped = false

    init(left: URL, right: URL) {
        self.left = left
        self.right = right
        self.leftFile = left.appendingPathComponent("clip.mov")
        self.rightFile = right.appendingPathComponent("clip.mov")
    }

    func selectSourceFolder() async -> URL? { nil }
    func selectDestinationFolders() async -> [URL] { [] }
    func selectLeftFolder() async -> URL? { left }
    func selectRightFolder() async -> URL? { right }
    func validateFileAccess(url: URL) async -> Bool { true }

    func startAccessing(url: URL) -> Bool {
        lock.lock()
        activeScopes[url.path, default: 0] += 1
        lock.unlock()
        return true
    }

    func stopAccessing(url: URL) {
        lock.lock()
        activeScopes[url.path, default: 0] = max(0, activeScopes[url.path, default: 0] - 1)
        lock.unlock()
    }

    func getFileList(from folderURL: URL) async throws -> [URL] {
        guard activeScopeCount(for: folderURL) > 0 else {
            throw ScopeTrackingError.missingScope("enumerating \(folderURL.path)")
        }
        if folderURL == left { return [leftFile] }
        if folderURL == right { return [rightFile] }
        return []
    }

    nonisolated func getFileSize(for url: URL) throws -> Int64 {
        guard let base = baseURL(containing: url), activeScopeCount(for: base) > 0 else {
            throw ScopeTrackingError.missingScope("sizing \(url.path)")
        }
        lock.lock()
        didReadSizesWhileScoped = true
        lock.unlock()
        return 10
    }

    nonisolated func createDirectory(at url: URL) throws {}
    nonisolated func freeSpace(at url: URL) -> Int64 { 1_000_000_000 }

    nonisolated func activeScopeCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activeScopes[url.path, default: 0]
    }

    private nonisolated func baseURL(containing url: URL) -> URL? {
        if url.path.hasPrefix(left.path + "/") { return left }
        if url.path.hasPrefix(right.path + "/") { return right }
        return nil
    }
}

private final class ScopeTrackingChecksumService: ChecksumService {
    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> String {
        "hash"
    }

    func verifyFileIntegrity(
        sourceURL: URL,
        destinationURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> VerificationResult {
        VerificationResult(
            sourceChecksum: "hash",
            destinationChecksum: "hash",
            matches: true,
            checksumType: type,
            processingTime: 0,
            fileSize: 10
        )
    }

    func performByteComparison(
        sourceURL: URL,
        destinationURL: URL,
        progressCallback: ProgressCallback?
    ) async throws -> Bool {
        true
    }
}

private final class ScopeTrackingFileOperationsService: FileOperationsService {
    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64?,
        progressCallback: @escaping ProgressCallback,
        onFileResult: FileResultCallback?
    ) async throws -> FileOperation {
        FileOperation(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            startTime: Date(),
            endTime: Date(),
            results: [],
            verificationMode: verificationMode,
            settings: settings,
            estimatedTotalBytes: estimatedTotalBytes
        )
    }

    func cancelOperation() {}
    func pauseOperation() async {}
    func resumeOperation() async {}
}

private final class ScopeTrackingCameraDetectionService: CameraDetectionService {
    func detectCamera(from folderURL: URL) async -> CameraDetectionResult {
        CameraDetectionResult(
            cameraCard: nil,
            confidence: 0,
            metadata: [:],
            detectionMethod: "test",
            processingTime: 0
        )
    }

    func analyzeFolderStructure(at url: URL) async throws -> [String: Any] { [:] }
    func extractVideoMetadata(from fileURL: URL) async throws -> [String: Any] { [:] }
    func parseXMLMetadata(from fileURL: URL) async throws -> [String: Any] { [:] }
}

private final class ScopeTrackingPlatformManager: PlatformManager {
    nonisolated let fileSystem: FileSystemService
    nonisolated let checksum: ChecksumService = ScopeTrackingChecksumService()
    nonisolated let fileOperations: FileOperationsService = ScopeTrackingFileOperationsService()
    nonisolated let cameraDetection: CameraDetectionService = ScopeTrackingCameraDetectionService()
    nonisolated let supportsDragAndDrop = false

    init(fileSystem: FileSystemService) {
        self.fileSystem = fileSystem
    }

    func presentAlert(title: String, message: String) async {}
    func presentError(_ error: Error) async {}
    func openURL(_ url: URL) async -> Bool { false }
}
