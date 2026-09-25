import Foundation
import XCTest
import CryptoKit
@testable import BitMatch

@MainActor
final class LocalTransferQueueIntegrationTests: XCTestCase {
    func testRealTwoCardQueueCopiesVerifiesAndPersistsBothAttempts() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let secondSource = f.root.appendingPathComponent("second-card")
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        try Data("second card has different contents".utf8).write(to: secondSource.appendingPathComponent("clip.mov"))
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        var reports = ReportPrefs()
        reports.makeReport = false
        let firstID = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                          cameraSettings: CameraLabelSettings(), reportSettings: reports, generateASCMHL: false)
        let secondID = try journal.enqueue(sourceURL: secondSource, destinationURLs: [f.destination], verificationMode: .standard,
                                           cameraSettings: CameraLabelSettings(), reportSettings: reports, generateASCMHL: false)
        let operations = SharedFileOperationsService(fileSystem: MacOSFileSystemService.shared, checksum: SharedChecksumService.shared)
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: operations), transferJournal: journal)
        coordinator.startQueue()
        let finished = await waitUntil(timeout: .seconds(15)) { @MainActor in
            !coordinator.queueIsRunning && !coordinator.isOperationInProgress
        }
        if !finished {
            coordinator.cancelOperation()
            _ = await waitUntil(timeout: .seconds(5)) { @MainActor in !coordinator.isOperationInProgress }
        }
        XCTAssertTrue(finished, coordinator.queueMessage ?? "Queue did not finish")
        let first = try XCTUnwrap(journal.records.first { $0.id == firstID })
        let second = try XCTUnwrap(journal.records.first { $0.id == secondID })
        XCTAssertEqual(first.state, .completed, first.summary)
        XCTAssertEqual(second.state, .completed, second.summary)
        XCTAssertEqual(first.results.count, 1)
        XCTAssertEqual(second.results.count, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(first.endedAt), try XCTUnwrap(second.startedAt))
        for record in [first, second] {
            let row = try XCTUnwrap(record.results.first)
            XCTAssertTrue(row.isSuccessStatus)
            let sourceData = try Data(contentsOf: URL(fileURLWithPath: row.path))
            let copiedData = try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(row.destinationPath)))
            XCTAssertEqual(sourceData, copiedData)
            let digest = SHA256.hash(data: copiedData).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(row.checksum?.lowercased(), digest)
        }
        let onDisk = try JSONDecoder().decode([LocalTransferRecord].self, from: Data(contentsOf: f.journalURL))
        XCTAssertEqual(onDisk.count, 2)
        XCTAssertTrue(onDisk.allSatisfy { $0.state == .completed && $0.results.count == 1 })
    }

    func testCompletionExportUsesRetainedRecordWithProvenance() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        var reports = ReportPrefs()
        reports.projectName = "Venice Shoot"
        reports.makeReport = false
        let id = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                     cameraSettings: CameraLabelSettings(), reportSettings: reports, generateASCMHL: true)
        let operations = SharedFileOperationsService(fileSystem: MacOSFileSystemService.shared, checksum: SharedChecksumService.shared)
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: operations), transferJournal: journal)
        coordinator.startQueue()
        let finished = await waitUntil(timeout: .seconds(15)) { @MainActor in
            !coordinator.queueIsRunning && !coordinator.isOperationInProgress
        }
        XCTAssertTrue(finished, coordinator.queueMessage ?? "Queue did not finish")
        XCTAssertEqual(journal.records.first { $0.id == id }?.state, .completed)

        let json = try coordinator.completionExportDocument(asCSV: false)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: json.data) as? [String: Any])
        XCTAssertEqual(payload["projectName"] as? String, "Venice Shoot")
        XCTAssertEqual(payload["ascMHLRequested"] as? Bool, true)
        XCTAssertEqual((payload["results"] as? [[String: Any]])?.count, 1)

        let csv = try coordinator.completionExportDocument(asCSV: true)
        XCTAssertTrue(String(decoding: csv.data, as: UTF8.self).contains("\"Venice Shoot\",\"requested\""))
    }

    func testFailedRequestedReportKeepsIssuesHistoryAndStopsQueue() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        // A file where the Reports folder belongs makes the requested export fail
        // while the media copy itself verifies.
        try Data("block".utf8).write(to: f.destination.appendingPathComponent("Reports"))
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        var reports = ReportPrefs()
        reports.makeReport = true
        let id = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                     cameraSettings: CameraLabelSettings(), reportSettings: reports, generateASCMHL: false)
        let operations = SharedFileOperationsService(fileSystem: MacOSFileSystemService.shared, checksum: SharedChecksumService.shared)
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: operations), transferJournal: journal)
        coordinator.startQueue()
        let finished = await waitUntil(timeout: .seconds(15)) { @MainActor in
            !coordinator.queueIsRunning && !coordinator.isOperationInProgress
        }
        XCTAssertTrue(finished, coordinator.queueMessage ?? "Queue did not finish")
        let record = try XCTUnwrap(journal.records.first { $0.id == id })
        XCTAssertEqual(record.state, .issues)
        XCTAssertTrue(record.results.first?.isSuccessStatus == true)
        XCTAssertTrue(record.summary.contains("Operation completed successfully"))
        XCTAssertTrue(record.summary.contains("report export failed"))
        XCTAssertFalse(coordinator.queueIsRunning)
    }

    func testCompletionExportWithoutFinishedTransferExplainsNextStep() throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        let service = QueueRecordingOperations()
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        XCTAssertThrowsError(try coordinator.completionExportDocument(asCSV: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No finished transfer"))
        }
    }

    func testStartingQueueDuringComparisonExplainsHowToContinue() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        let service = QueueRecordingOperations()
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        coordinator.currentMode = .compareFolders
        coordinator.isOperationInProgress = true
        coordinator.startQueue()
        XCTAssertFalse(coordinator.queueIsRunning)
        XCTAssertEqual(coordinator.queueMessage, "Finish or cancel the folder comparison, then choose Run queue.")
        let starts = await service.starts
        XCTAssertTrue(starts.isEmpty)
        coordinator.isOperationInProgress = false
    }

    func testQueueUsesSavedSnapshotAndStopsWhenResultsAreEmpty() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        var camera = CameraLabelSettings()
        camera.label = "Saved A001"
        var reports = ReportPrefs()
        reports.makeReport = false
        let firstID = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                          cameraSettings: camera, reportSettings: reports, generateASCMHL: false)
        let secondID = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                           cameraSettings: camera, reportSettings: reports, generateASCMHL: false)
        let service = QueueRecordingOperations()
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        coordinator.cameraLabelSettings.label = "Unsaved changed label"
        coordinator.verificationMode = .quick
        coordinator.sourceURL = f.destination
        coordinator.destinationURLs = [f.source]
        coordinator.startQueue()
        let finished = await waitUntil { @MainActor in
            !coordinator.queueIsRunning && !coordinator.isOperationInProgress
        }
        XCTAssertTrue(finished)
        let starts = await service.starts
        XCTAssertEqual(starts.count, 1, "An empty/unverified result must stop the queue")
        XCTAssertEqual(starts.first?.label, "Saved A001")
        XCTAssertEqual(starts.first?.mode, .standard)
        XCTAssertEqual(starts.first?.source.resolvingSymlinksInPath(), f.source.resolvingSymlinksInPath())
        XCTAssertEqual(starts.first?.destinations.map { $0.resolvingSymlinksInPath() }, [f.destination.resolvingSymlinksInPath()])
        XCTAssertEqual(journal.records.first(where: { $0.id == firstID })?.state, .issues)
        XCTAssertEqual(journal.records.first(where: { $0.id == secondID })?.state, .queued)
    }

    func testPersistenceFailureNeverStartsFileOperation() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        try Data("corrupt history".utf8).write(to: f.journalURL)
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        let service = QueueRecordingOperations()
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        coordinator.sourceURL = f.source
        coordinator.destinationURLs = [f.destination]
        await coordinator.startOperation()
        let starts = await service.starts
        XCTAssertTrue(starts.isEmpty)
        XCTAssertFalse(coordinator.isOperationInProgress)
        XCTAssertNotNil(coordinator.queueMessage)
        XCTAssertEqual(try String(contentsOf: f.journalURL, encoding: .utf8), "corrupt history")
    }

    func testCancellationStopsQueueUntilUserStartsItAgain() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        var reports = ReportPrefs()
        reports.makeReport = false
        let firstID = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                          cameraSettings: CameraLabelSettings(), reportSettings: reports, generateASCMHL: false)
        let secondID = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                           cameraSettings: CameraLabelSettings(), reportSettings: reports, generateASCMHL: false)
        let service = QueueRecordingOperations(blocked: true)
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        coordinator.startQueue()
        let started = await waitUntil { await service.starts.count == 1 }
        XCTAssertTrue(started)
        XCTAssertThrowsError(try coordinator.completionExportDocument(asCSV: false),
                             "A running journal record is not a finished report")
        coordinator.cancelOperation()
        XCTAssertTrue(coordinator.isOperationInProgress, "Restart must stay disabled until cancellation unwinds")
        await service.release()
        let finished = await waitUntil { @MainActor in !coordinator.isOperationInProgress }
        XCTAssertTrue(finished)
        XCTAssertFalse(coordinator.queueIsRunning)
        let starts = await service.starts
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(journal.records.first(where: { $0.id == firstID })?.state, .cancelled)
        XCTAssertEqual(journal.records.first(where: { $0.id == secondID })?.state, .queued)
    }

    func testQueueDoesNotReplayProjectRecord() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        let id = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                     cameraSettings: CameraLabelSettings(), reportSettings: ReportPrefs(), projectID: UUID())
        let service = QueueRecordingOperations()
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        coordinator.startQueue()
        let stopped = await waitUntil { @MainActor in !coordinator.queueIsRunning }
        XCTAssertTrue(stopped)
        let starts = await service.starts
        XCTAssertTrue(starts.isEmpty)
        XCTAssertEqual(journal.records.first(where: { $0.id == id })?.state, .queued)
    }

    func testDisconnectedQueuedDestinationDoesNotFallThroughToNextCard() async throws {
        let f = try QueueFixture()
        defer { f.cleanup() }
        let journal = LocalTransferJournal(fileURL: f.journalURL)
        let id = try journal.enqueue(sourceURL: f.source, destinationURLs: [f.destination], verificationMode: .standard,
                                     cameraSettings: CameraLabelSettings(), reportSettings: ReportPrefs())
        try FileManager.default.removeItem(at: f.destination)
        let service = QueueRecordingOperations()
        let coordinator = SharedAppCoordinator(platformManager: QueuePlatformManager(fileOperations: service), transferJournal: journal)
        coordinator.startQueue()
        let stopped = await waitUntil { @MainActor in !coordinator.queueIsRunning }
        XCTAssertTrue(stopped)
        let starts = await service.starts
        XCTAssertTrue(starts.isEmpty)
        XCTAssertEqual(journal.records.first(where: { $0.id == id })?.state, .interrupted)
        XCTAssertNotNil(coordinator.queueMessage)
    }
}

private struct QueueFixture {
    let root: URL
    let source: URL
    let destination: URL
    var journalURL: URL { root.appendingPathComponent("history.json") }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = root.appendingPathComponent("source")
        destination = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("card".utf8).write(to: source.appendingPathComponent("clip.mov"))
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private struct QueueStartSnapshot {
    let source: URL
    let destinations: [URL]
    let label: String
    let mode: VerificationMode
}

private actor QueueGate {
    var starts: [QueueStartSnapshot] = []
    var blocked: Bool
    var waiters: [CheckedContinuation<Void, Never>] = []
    init(blocked: Bool) { self.blocked = blocked }
    func record(_ snapshot: QueueStartSnapshot) async {
        starts.append(snapshot)
        if blocked { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() {
        blocked = false
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

private final class QueueRecordingOperations: FileOperationsService, @unchecked Sendable {
    private let gate: QueueGate
    init(blocked: Bool = false) { gate = QueueGate(blocked: blocked) }
    var starts: [QueueStartSnapshot] { get async { await gate.starts } }
    func release() async { await gate.release() }
    func performFileOperation(sourceURL: URL, destinationURLs: [URL], verificationMode: VerificationMode,
                              settings: CameraLabelSettings, estimatedTotalBytes: Int64?,
                              progressCallback: @escaping ProgressCallback, onFileResult: FileResultCallback?) async throws -> FileOperation {
        await gate.record(QueueStartSnapshot(source: sourceURL, destinations: destinationURLs, label: settings.label, mode: verificationMode))
        return FileOperation(sourceURL: sourceURL, destinationURLs: destinationURLs, startTime: Date(), endTime: Date(),
                             results: [], verificationMode: verificationMode, settings: settings, estimatedTotalBytes: estimatedTotalBytes)
    }
    func cancelOperation() {}
    func pauseOperation() async {}
    func resumeOperation() async {}
}

private final class QueuePlatformManager: PlatformManager {
    nonisolated let fileSystem: FileSystemService = FakeFileSystemService()
    nonisolated let checksum: ChecksumService = QueueChecksumService()
    nonisolated let fileOperations: FileOperationsService
    nonisolated let cameraDetection: CameraDetectionService = QueueCameraDetectionService()
    nonisolated let supportsDragAndDrop = false

    init(fileOperations: FileOperationsService) {
        self.fileOperations = fileOperations
    }

    func presentAlert(title: String, message: String) async {}
    func presentError(_ error: Error) async {}
    func openURL(_ url: URL) async -> Bool { false }
}

private final class QueueChecksumService: ChecksumService {
    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> String { "hash" }

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
            fileSize: 0
        )
    }

    func performByteComparison(
        sourceURL: URL,
        destinationURL: URL,
        progressCallback: ProgressCallback?
    ) async throws -> Bool { true }
}

private final class QueueCameraDetectionService: CameraDetectionService {
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
