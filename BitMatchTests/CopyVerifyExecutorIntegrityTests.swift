import Foundation
import CryptoKit
import XCTest
@testable import BitMatch

@MainActor
final class CopyVerifyExecutorIntegrityTests: XCTestCase {
    func testReturnedOperationFailureControlsCompletionWithoutPresentationCallback() async throws {
        let failure = FileOperationResult(
            sourceURL: URL(fileURLWithPath: "/source/clip.mov"),
            destinationURL: URL(fileURLWithPath: "/destination/clip.mov"),
            success: false,
            error: NSError(domain: "test", code: 1),
            fileSize: 10,
            verificationResult: nil,
            processingTime: 0
        )
        let harness = ExecutorHarness(returnedResults: [failure], emittedResults: [])

        _ = try await harness.execute()

        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertFalse(harness.completedRows[0].isSuccessStatus)
        XCTAssertEqual(harness.terminalInfo?.success, false)
    }

    func testLifecycleFailureDowngradesCompletionAndStillPublishesAuthoritativeRows() async throws {
        let success = FileOperationResult(
            sourceURL: URL(fileURLWithPath: "/source/clip.mov"),
            destinationURL: URL(fileURLWithPath: "/destination/clip.mov"),
            success: true,
            error: nil,
            fileSize: 10,
            verificationResult: VerificationResult(
                sourceChecksum: "checksum",
                destinationChecksum: "checksum",
                matches: true,
                checksumType: .sha256,
                processingTime: 0,
                fileSize: 10
            ),
            processingTime: 0
        )
        let harness = ExecutorHarness(
            returnedResults: [success],
            emittedResults: [],
            lifecycleCompletion: { _ in throw ExecutorFixtureError.persistence }
        )

        _ = try await harness.execute()

        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertTrue(harness.completedRows[0].isSuccessStatus)
        XCTAssertEqual(harness.terminalInfo?.success, false)
    }

    func testUnsafePersistedPhotographerVerdictDowngradesCompletionWithoutDiscardingRows() async throws {
        let success = FileOperationResult(
            sourceURL: URL(fileURLWithPath: "/source/clip.mov"),
            destinationURL: URL(fileURLWithPath: "/destination/clip.mov"),
            success: true,
            error: nil,
            fileSize: 10,
            verificationResult: VerificationResult(
                sourceChecksum: "checksum",
                destinationChecksum: "checksum",
                matches: true,
                checksumType: .sha256,
                processingTime: 0,
                fileSize: 10
            ),
            processingTime: 0
        )
        let harness = ExecutorHarness(
            returnedResults: [success],
            emittedResults: [],
            lifecycleCompletion: { _ in
                PhotographerFinalizationResult(context: nil, locallySafe: false)
            }
        )

        _ = try await harness.execute()

        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertTrue(harness.completedRows[0].isSuccessStatus)
        XCTAssertEqual(harness.terminalInfo?.success, false)
        XCTAssertTrue(harness.terminalInfo?.message.contains("photographer verification is incomplete") == true)
    }
    func testEmptyAuthoritativeResultsCannotCompleteSuccessfully() async throws {
        let harness = ExecutorHarness(returnedResults: [], emittedResults: [])
        _ = try await harness.execute()
        XCTAssertEqual(harness.terminalInfo?.success, false)
        XCTAssertEqual(harness.terminalInfo?.message, "No files were verified")
    }

    func testFailedRequestedReportDowngradesCompletionButKeepsVerifiedRows() async throws {
        let fixture = try reportFixture(blockReportsFolder: true)
        let harness = ExecutorHarness(returnedResults: [fixture.result], emittedResults: [],
            sourceURL: fixture.source, destinationURLs: [fixture.destination], makeReport: true)
        _ = try await harness.execute()
        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertTrue(harness.completedRows[0].isSuccessStatus)
        XCTAssertEqual(harness.terminalInfo?.success, false)
        XCTAssertTrue(harness.terminalInfo?.message.contains("Operation completed successfully") == true)
        XCTAssertTrue(harness.terminalInfo?.message.contains("report export failed") == true)
    }

    func testSuccessfulRequestedReportKeepsSuccessfulCompletion() async throws {
        let fixture = try reportFixture(blockReportsFolder: false)
        let harness = ExecutorHarness(returnedResults: [fixture.result], emittedResults: [],
            sourceURL: fixture.source, destinationURLs: [fixture.destination], makeReport: true)
        _ = try await harness.execute()
        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertTrue(harness.completedRows[0].isSuccessStatus)
        XCTAssertEqual(harness.terminalInfo?.success, true)
        XCTAssertTrue(harness.terminalInfo?.message.contains("report export failed") == false)
        let saved = try FileManager.default.contentsOfDirectory(
            at: fixture.destination.appendingPathComponent("Reports"), includingPropertiesForKeys: nil)
        XCTAssertTrue(saved.contains { $0.pathExtension == "csv" })
        XCTAssertTrue(saved.contains { $0.pathExtension == "json" })
    }

    func testVerifiedDestinationPublishesASCMHLBeforeSuccessfulCompletion() async throws {
        let fixture = try ascFixture()
        let harness = ExecutorHarness(returnedResults: [fixture.result], emittedResults: [],
            sourceURL: fixture.source, destinationURLs: [fixture.destination], generateASCMHL: true)
        _ = try await harness.execute()
        XCTAssertEqual(harness.terminalInfo?.success, true)
        XCTAssertTrue(harness.terminalInfo?.message.contains("ASC MHL handoff records saved") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.history.appendingPathComponent("ascmhl_chain.xml").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("ascmhl").path))
        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertTrue(harness.completedRows[0].isSuccessStatus)
    }

    func testHandoffFailurePreservesSuccessfulFileRowsAndPhotographerFinalization() async throws {
        let fixture = try ascFixture()
        try Data("corrupted".utf8).write(to: fixture.result.destinationURL)
        var finalizations = 0
        let harness = ExecutorHarness(returnedResults: [fixture.result], emittedResults: [], lifecycleCompletion: { _ in
            finalizations += 1
            return PhotographerFinalizationResult(context: nil, locallySafe: true)
        }, sourceURL: fixture.source, destinationURLs: [fixture.destination], generateASCMHL: true)
        _ = try await harness.execute()
        XCTAssertEqual(finalizations, 1)
        XCTAssertEqual(harness.terminalInfo?.success, false)
        XCTAssertTrue(harness.terminalInfo?.message.contains("ASC MHL") == true)
        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertTrue(harness.completedRows[0].isSuccessStatus)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.history.path))
    }

    func testFailedCopyDoesNotPublishShortenedASCInventory() async throws {
        let fixture = try ascFixture()
        let failure = FileOperationResult(sourceURL: fixture.source.appendingPathComponent("missing.mov"),
            destinationURL: fixture.result.destinationURL.deletingLastPathComponent().appendingPathComponent("missing.mov"),
            success: false, error: ExecutorFixtureError.persistence, fileSize: 10, verificationResult: nil, processingTime: 0)
        let harness = ExecutorHarness(returnedResults: [fixture.result, failure], emittedResults: [],
            sourceURL: fixture.source, destinationURLs: [fixture.destination], generateASCMHL: true)
        _ = try await harness.execute()
        XCTAssertEqual(harness.terminalInfo?.success, false)
        XCTAssertEqual(harness.completedRows.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.history.path))
    }

    func testQuickModeKeepsFailureAndUnverifiedWarningWithoutASC() async throws {
        let fixture = try ascFixture()
        let failure = FileOperationResult(sourceURL: fixture.result.sourceURL, destinationURL: fixture.result.destinationURL,
            success: false, error: ExecutorFixtureError.persistence, fileSize: 10, verificationResult: nil, processingTime: 0)
        let harness = ExecutorHarness(returnedResults: [failure], emittedResults: [],
            sourceURL: fixture.source, destinationURLs: [fixture.destination], verificationMode: .quick, generateASCMHL: true)
        _ = try await harness.execute()
        XCTAssertEqual(harness.terminalInfo?.success, false)
        XCTAssertTrue(harness.terminalInfo?.message.contains("1 issue") == true)
        XCTAssertTrue(harness.terminalInfo?.message.lowercased().contains("not been checksum verified") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.history.path))
    }

    func testAutomaticChecksumManifestRetainsVerifiedEvidenceAndDistinctPaths() throws {
        let fixture = TestFixture()
        let output = fixture.directory.appendingPathComponent("checksums.txt")
        let rows = [
            ResultRow(path: "/source/a/clip.mov", status: "✅ Match", size: 10, checksum: "first",
                      destination: "Backup", destinationPath: "/backup/a/clip.mov"),
            ResultRow(path: "/source/b/clip.mov", status: "✅ Match", size: 10, checksum: "second",
                      destination: "Backup", destinationPath: "/backup/b/clip.mov")
        ]
        // No source or destination files are needed: export must preserve the
        // recorded verification, not silently recalculate or omit missing media.
        try ReportExporter.writeRecordedChecksumManifest(results: rows, algorithm: .sha256, to: output)
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.contains("first  /backup/a/clip.mov"))
        XCTAssertTrue(text.contains("second  /backup/b/clip.mov"))
        XCTAssertThrowsError(try ReportExporter.writeRecordedChecksumManifest(
            results: rows, algorithm: .sha256, to: fixture.directory.appendingPathComponent("missing/report.txt")))
    }

    func testMissingChecksumCannotProduceSuccessfulManifest() throws {
        let fixture = TestFixture()
        let output = fixture.directory.appendingPathComponent("checksums.txt")
        let row = ResultRow(path: "/source/clip.mov", status: "✅ Match", size: 10, checksum: nil, destination: "Backup")
        XCTAssertThrowsError(try ReportExporter.writeRecordedChecksumManifest(results: [row], algorithm: .sha256, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCancellationAfterVerificationDoesNotPublishCompletionOrReports() async throws {
        let fixture = try reportFixture(blockReportsFolder: false)
        let harness = ExecutorHarness(returnedResults: [fixture.result], emittedResults: [],
            sourceURL: fixture.source, destinationURLs: [fixture.destination], makeReport: true)
        harness.onAuthoritativeResults = { harness.cancel() }
        do {
            _ = try await harness.execute()
            XCTFail("Cancelled finalization must throw")
        } catch is CancellationError { }
        XCTAssertNil(harness.terminalInfo)
        XCTAssertEqual(harness.completedRows.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("Reports").path))
    }

    private func reportFixture(blockReportsFolder: Bool) throws -> (source: URL, destination: URL, result: FileOperationResult) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("executor-report-\(UUID())")
        addTeardownBlock { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("card")
        let destination = root.appendingPathComponent("backup")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let bytes = Data("verified bytes for report outcome".utf8)
        try bytes.write(to: source.appendingPathComponent("clip.mov"))
        if blockReportsFolder {
            // A file where the Reports folder belongs makes the requested export fail.
            try bytes.write(to: destination.appendingPathComponent("Reports"))
        }
        let result = FileOperationResult(sourceURL: source.appendingPathComponent("clip.mov"),
            destinationURL: destination.appendingPathComponent("clip.mov"),
            success: true, error: nil, fileSize: Int64(bytes.count),
            verificationResult: VerificationResult(sourceChecksum: "report", destinationChecksum: "report",
                matches: true, checksumType: .sha256, processingTime: 0, fileSize: Int64(bytes.count)),
            processingTime: 0)
        return (source, destination, result)
    }

    private func ascFixture() throws -> (source: URL, destination: URL, history: URL, result: FileOperationResult) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("executor-asc-\(UUID())")
        addTeardownBlock { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("card")
        let destination = root.appendingPathComponent("backup")
        let copiedRoot = SafetyValidator.resolvedDestinationRoot(source: source, destination: destination, settings: CameraLabelSettings())
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: copiedRoot, withIntermediateDirectories: true)
        let sourceFile = source.appendingPathComponent("clip.mov")
        let copyFile = copiedRoot.appendingPathComponent("clip.mov")
        let bytes = Data("Real bytes for executor handoff verification".utf8)
        try bytes.write(to: sourceFile)
        try bytes.write(to: copyFile)
        let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let result = FileOperationResult(sourceURL: sourceFile, destinationURL: copyFile, success: true, error: nil,
            fileSize: Int64(bytes.count), verificationResult: VerificationResult(sourceChecksum: checksum,
                destinationChecksum: checksum, matches: true, checksumType: .sha256, processingTime: 0,
                fileSize: Int64(bytes.count)), processingTime: 0)
        return (source, destination, copiedRoot.appendingPathComponent("ascmhl"), result)
    }

}

@MainActor
private final class ExecutorHarness {
    private let executor: CopyVerifyExecutor
    private let config: CopyVerifyConfig

    private(set) var completedRows: [ResultRow] = []
    private(set) var terminalInfo: OperationCompletionInfo?
    var onAuthoritativeResults: (() -> Void)?

    func cancel() { executor.cancel() }

    init(
        returnedResults: [FileOperationResult],
        emittedResults: [FileOperationResult],
        lifecycleCompletion: (@MainActor ([ResultRow]) throws -> PhotographerFinalizationResult)? = nil,
        sourceURL: URL = URL(fileURLWithPath: "/source"),
        destinationURLs: [URL] = [URL(fileURLWithPath: "/destination")],
        verificationMode: VerificationMode = .standard,
        generateASCMHL: Bool = false,
        makeReport: Bool = false
    ) {
        let fileOperations = ExecutorFileOperationsService(
            returnedResults: returnedResults,
            emittedResults: emittedResults
        )
        let platform = ExecutorPlatformManager(fileOperations: fileOperations)
        executor = CopyVerifyExecutor(
            platformManager: platform,
            timingService: OperationTimingService(),
            errorService: ErrorReportingService(),
            stateService: OperationStateService(),
            backgroundTaskService: IOSBackgroundTaskService.shared
        )
        config = CopyVerifyConfig(
            operationId: UUID(),
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            verificationMode: verificationMode,
            cameraLabelSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(makeReport: makeReport),
            estimatedFiles: returnedResults.count,
            estimatedBytes: returnedResults.reduce(0) { $0 + $1.fileSize },
            currentMode: .copyAndVerify,
            photographerReportFinalizer: lifecycleCompletion,
            generateASCMHL: generateASCMHL
        )
    }

    func execute() async throws -> FileOperation? {
        try await executor.execute(
            config: config,
            callbacks: CopyVerifyCallbacks(
                onProgress: { _ in },
                onResult: { _ in },
                onStateChange: { [weak self] state in
                    guard case .completed(let info) = state else { return }
                    self?.terminalInfo = info
                },
                onAuthoritativeResults: { [weak self] rows in
                    guard let self else { return }
                    self.completedRows = rows
                    self.onAuthoritativeResults?()
                }
            )
        )
    }
}

private enum ExecutorFixtureError: Error {
    case persistence
}

private final class ExecutorFileOperationsService: FileOperationsService {
    private let returnedResults: [FileOperationResult]
    private let emittedResults: [FileOperationResult]

    init(returnedResults: [FileOperationResult], emittedResults: [FileOperationResult]) {
        self.returnedResults = returnedResults
        self.emittedResults = emittedResults
    }

    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64?,
        progressCallback: @escaping ProgressCallback,
        onFileResult: FileResultCallback?
    ) async throws -> FileOperation {
        for result in emittedResults {
            await onFileResult?(result)
        }
        return FileOperation(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            startTime: Date(),
            endTime: Date(),
            results: returnedResults,
            verificationMode: verificationMode,
            settings: settings,
            estimatedTotalBytes: estimatedTotalBytes
        )
    }

    func cancelOperation() {}
    func pauseOperation() async {}
    func resumeOperation() async {}
}

private final class ExecutorPlatformManager: PlatformManager {
    nonisolated let fileSystem: FileSystemService = ExecutorFileSystemService()
    nonisolated let checksum: ChecksumService = ExecutorChecksumService()
    nonisolated let fileOperations: FileOperationsService
    nonisolated let cameraDetection: CameraDetectionService = ExecutorCameraDetectionService()
    nonisolated let supportsDragAndDrop = false

    init(fileOperations: FileOperationsService) {
        self.fileOperations = fileOperations
    }

    func presentAlert(title: String, message: String) async {}
    func presentError(_ error: Error) async {}
    func openURL(_ url: URL) async -> Bool { false }
}

private final class ExecutorFileSystemService: FileSystemService {
    func selectSourceFolder() async -> URL? { nil }
    func selectDestinationFolders() async -> [URL] { [] }
    func selectLeftFolder() async -> URL? { nil }
    func selectRightFolder() async -> URL? { nil }
    func validateFileAccess(url: URL) async -> Bool { true }
    func startAccessing(url: URL) -> Bool { true }
    func stopAccessing(url: URL) {}
    func getFileList(from folderURL: URL) async throws -> [URL] { [] }
    nonisolated func getFileSize(for url: URL) throws -> Int64 { 0 }
    nonisolated func createDirectory(at url: URL) throws {}
    nonisolated func freeSpace(at url: URL) -> Int64 { .max }
}

private final class ExecutorChecksumService: ChecksumService {
    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> String { "" }

    func verifyFileIntegrity(
        sourceURL: URL,
        destinationURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> VerificationResult {
        VerificationResult(
            sourceChecksum: "",
            destinationChecksum: "",
            matches: true,
            checksumType: type,
            processingTime: 0,
            fileSize: 0
        )
    }

    func performByteComparison(
        sourceURL: URL,
        destinationURL: URL,
        progressCallback: ProgressCallback?
    ) async throws -> Bool { true }
}

private final class ExecutorCameraDetectionService: CameraDetectionService {
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
