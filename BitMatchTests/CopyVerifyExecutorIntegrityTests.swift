import Foundation
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
}

@MainActor
private final class ExecutorHarness {
    private let executor: CopyVerifyExecutor
    private let config: CopyVerifyConfig

    private(set) var completedRows: [ResultRow] = []
    private(set) var terminalInfo: OperationCompletionInfo?

    init(
        returnedResults: [FileOperationResult],
        emittedResults: [FileOperationResult],
        lifecycleCompletion: (@MainActor ([ResultRow]) throws -> PhotographerFinalizationResult)? = nil
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
            sourceURL: URL(fileURLWithPath: "/source"),
            destinationURLs: [URL(fileURLWithPath: "/destination")],
            verificationMode: .standard,
            cameraLabelSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(makeReport: false),
            estimatedFiles: returnedResults.count,
            estimatedBytes: returnedResults.reduce(0) { $0 + $1.fileSize },
            currentMode: .copyAndVerify,
            photographerReportFinalizer: lifecycleCompletion
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
