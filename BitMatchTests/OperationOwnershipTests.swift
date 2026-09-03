import Foundation
import XCTest
@testable import BitMatch

final class OperationOwnershipTests: XCTestCase {
    func testSecondOperationIsRejectedWhileFirstIsActive() async throws {
        try await FileOperationsTestLock.shared.run {
            let fixture = try OwnershipTransferFixture(destinationCount: 2)
            defer { fixture.cleanup() }
            let checksum = BlockingChecksumService()
            let service = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: checksum
            )
            let firstFinished = AsyncFlag()

            let first = Task { () -> Result<FileOperation, Error> in
                let result: Result<FileOperation, Error>
                do {
                    result = .success(try await service.performFileOperation(
                        sourceURL: fixture.source,
                        destinationURLs: [fixture.destinations[0]],
                        verificationMode: .standard,
                        settings: CameraLabelSettings(),
                        estimatedTotalBytes: nil,
                        progressCallback: { _ in },
                        onFileResult: nil
                    ))
                } catch {
                    result = .failure(error)
                }
                await firstFinished.set()
                return result
            }

            let verifierStarted = await waitUntil { await checksum.didStart }
            XCTAssertTrue(verifierStarted)

            let secondError: Error?
            do {
                _ = try await service.performFileOperation(
                    sourceURL: fixture.source,
                    destinationURLs: [fixture.destinations[1]],
                    verificationMode: .quick,
                    settings: CameraLabelSettings(),
                    estimatedTotalBytes: nil,
                    progressCallback: { _ in },
                    onFileResult: nil
                )
                secondError = nil
            } catch {
                secondError = error
            }

            let firstWasStillActive = !(await firstFinished.value)
            await checksum.release()
            let firstResult = await first.value
            let firstVerifierWasCancelled = await checksum.didObserveCancellation

            XCTAssertEqual(
                secondError?.localizedDescription,
                "Another file operation is already active or cancelling."
            )
            XCTAssertTrue(firstWasStillActive, "The rejected start must not finish or replace the active operation")
            switch firstResult {
            case .success(let operation):
                XCTAssertEqual(operation.results.count, 1)
                XCTAssertTrue(operation.results.allSatisfy(\.success))
            case .failure(let error):
                XCTFail("Rejecting the second operation disturbed the first: \(error)")
            }
            XCTAssertFalse(firstVerifierWasCancelled, "Rejecting B must not cancel A's verifier")
        }
    }

    func testCallerCancellationOwnsVerifierCleanupBeforeReturning() async throws {
        try await FileOperationsTestLock.shared.run {
            let fixture = try OwnershipTransferFixture(destinationCount: 1)
            defer { fixture.cleanup() }
            let checksum = BlockingChecksumService()
            let service = SharedFileOperationsService(
                fileSystem: MacOSFileSystemService.shared,
                checksum: checksum
            )
            let callbackCount = AsyncCounter()
            let callerFinished = AsyncFlag()

            let caller = Task { () -> Result<FileOperation, Error> in
                let result: Result<FileOperation, Error>
                do {
                    result = .success(try await service.performFileOperation(
                        sourceURL: fixture.source,
                        destinationURLs: fixture.destinations,
                        verificationMode: .standard,
                        settings: CameraLabelSettings(),
                        estimatedTotalBytes: nil,
                        progressCallback: { _ in },
                        onFileResult: { _ in await callbackCount.increment() }
                    ))
                } catch {
                    result = .failure(error)
                }
                await callerFinished.set()
                return result
            }

            let verifierStarted = await waitUntil { await checksum.didStart }
            XCTAssertTrue(verifierStarted)

            caller.cancel()
            let verifierSawCancellation = await waitUntil(
                timeoutNanoseconds: 300_000_000,
                condition: { await checksum.didObserveCancellation }
            )
            let callerReturnedBeforeRelease = await callerFinished.value
            let callbacksBeforeRelease = await callbackCount.value

            await checksum.release()
            let callerResult = await caller.value
            try? await Task<Never, Never>.sleep(nanoseconds: 100_000_000)
            let callbacksAfterReturn = await callbackCount.value

            XCTAssertTrue(verifierSawCancellation, "Cancelling the caller must cancel its owned operation task")
            XCTAssertFalse(callerReturnedBeforeRelease, "Caller returned before cancellation-resistant verifier cleanup")
            if case .failure(let error) = callerResult {
                XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
            } else {
                XCTFail("Direct caller cancellation completed as success")
            }
            XCTAssertEqual(callbacksAfterReturn, callbacksBeforeRelease, "A callback escaped caller return")
        }
    }

    func testCancellationWaitsForVerifierCleanupBeforeOperationReturns() async throws {
        try await FileOperationsTestLock.shared.run {
            let fixture = try OwnershipTransferFixture(destinationCount: 2)
            defer { fixture.cleanup() }
            let checksum = BlockingChecksumService()
            let failingRoot = SafetyValidator.resolvedDestinationRoot(
                source: fixture.source,
                destination: fixture.destinations[1],
                settings: CameraLabelSettings()
            )
            let fileSystem = BlockingFailureFileSystem(failingDirectory: failingRoot)
            let failingDestination = fixture.destinations[1].standardizedFileURL
            let service = SharedFileOperationsService(
                fileSystem: fileSystem,
                checksum: checksum,
                destinationSetupHook: { destination in
                    guard destination.standardizedFileURL == failingDestination else { return }
                    try fileSystem.enterFailingDirectory()
                }
            )
            let callbackCount = AsyncCounter()
            let operationFinished = AsyncFlag()

            let operation = Task { () -> Result<FileOperation, Error> in
                let result: Result<FileOperation, Error>
                do {
                    result = .success(try await service.performFileOperation(
                        sourceURL: fixture.source,
                        destinationURLs: fixture.destinations,
                        verificationMode: .standard,
                        settings: CameraLabelSettings(),
                        estimatedTotalBytes: nil,
                        progressCallback: { _ in },
                        onFileResult: { _ in await callbackCount.increment() }
                    ))
                } catch {
                    result = .failure(error)
                }
                await operationFinished.set()
                return result
            }

            let verifierStarted = await waitUntil { await checksum.didStart }
            let failingDirectoryEntered = await waitUntil { fileSystem.didEnterFailingDirectory }
            XCTAssertTrue(verifierStarted)
            XCTAssertTrue(failingDirectoryEntered)

            service.cancelOperation()
            fileSystem.releaseFailingDirectory()

            let returnedBeforeVerifierRelease = await waitUntil(
                timeoutNanoseconds: 300_000_000,
                condition: { await operationFinished.value }
            )
            let verifierSawCancellation = await checksum.didObserveCancellation
            let callbacksBeforeVerifierRelease = await callbackCount.value
            await checksum.release()
            _ = await operation.value
            try? await Task<Never, Never>.sleep(nanoseconds: 100_000_000)
            let callbacksAfterReturn = await callbackCount.value

            XCTAssertFalse(returnedBeforeVerifierRelease, "Operation returned before verifier cleanup finished")
            XCTAssertTrue(verifierSawCancellation, "Cancelling the operation must cancel its verifier tasks")
            XCTAssertEqual(
                callbacksAfterReturn,
                callbacksBeforeVerifierRelease,
                "A verifier callback escaped operation return"
            )
        }
    }

    func testCancellationDuringDestinationSetupDoesNotFabricateFailureRows() async throws {
        try await FileOperationsTestLock.shared.run {
            let fixture = try OwnershipTransferFixture(destinationCount: 2)
            defer { fixture.cleanup() }
            let service = SharedFileOperationsService(
                fileSystem: OwnershipFileSystem(),
                checksum: SharedChecksumService.shared,
                destinationSetupHook: { _ in throw CancellationError() }
            )
            let callbackCount = AsyncCounter()

            do {
                _ = try await service.performFileOperation(
                    sourceURL: fixture.source,
                    destinationURLs: fixture.destinations,
                    verificationMode: .standard,
                    settings: CameraLabelSettings(),
                    estimatedTotalBytes: nil,
                    progressCallback: { _ in },
                    onFileResult: { _ in await callbackCount.increment() }
                )
                XCTFail("Cancellation during destination setup must propagate")
            } catch is CancellationError {
                // Expected.
            }

            let rows = await callbackCount.value
            XCTAssertEqual(rows, 0, "Cancellation must not be reported as per-file destination failures")
        }
    }

    @MainActor
    func testCoordinatorDoesNotEnableRestartUntilCancellationUnwinds() async throws {
        let fixture = try OwnershipTransferFixture(destinationCount: 1)
        defer { fixture.cleanup() }
        let fileOperations = BlockingFileOperationsService()
        let coordinator = SharedAppCoordinator(
            platformManager: OwnershipPlatformManager(fileOperations: fileOperations)
        )
        coordinator.sourceURL = fixture.source
        coordinator.destinationURLs = fixture.destinations

        let first = Task { @MainActor in await coordinator.startOperation() }
        let firstStartReachedService = await waitUntil { await fileOperations.startCount == 1 }
        XCTAssertTrue(firstStartReachedService)

        coordinator.cancelOperation()
        let second = Task { @MainActor in await coordinator.startOperation() }
        let startedTwiceBeforeUnwind = await waitUntil(
            timeoutNanoseconds: 300_000_000,
            condition: { await fileOperations.startCount == 2 }
        )

        await fileOperations.release()
        await first.value
        await second.value

        XCTAssertFalse(startedTwiceBeforeUnwind, "Coordinator allowed restart before cancellation unwound")
        let finalStartCount = await fileOperations.startCount
        XCTAssertEqual(finalStartCount, 1)
    }
}

private struct OwnershipTransferFixture {
    let root: URL
    let source: URL
    let destinations: [URL]

    init(destinationCount: Int) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitmatch-ownership-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
        let destinationURLs = (0..<destinationCount).map {
            rootURL.appendingPathComponent("destination-\($0)", isDirectory: true)
        }
        root = rootURL
        source = sourceURL
        destinations = destinationURLs
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for destination in destinations {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        try Data("ownership fixture".utf8).write(to: source.appendingPathComponent("clip.mov"))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor BlockingChecksumGate {
    private var started = false
    private var released = false
    private var cancellationObserved = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    var didStart: Bool { started }
    var didObserveCancellation: Bool { cancellationObserved }

    func begin() {
        started = true
    }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func observeCancellation() {
        cancellationObserved = true
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class BlockingChecksumService: ChecksumService, @unchecked Sendable {
    private let gate = BlockingChecksumGate()

    var didStart: Bool { get async { await gate.didStart } }
    var didObserveCancellation: Bool { get async { await gate.didObserveCancellation } }
    func release() async { await gate.release() }

    /// Verification (in production) is driven through `generateChecksum` for
    /// the source digest, so that call must gate/observe cancellation exactly
    /// like `verifyFileIntegrity` used to for these tests to exercise the
    /// same start/cancel/release timing.
    private func blockUntilReleasedOrCancelled() async throws {
        await gate.begin()
        await withTaskCancellationHandler {
            await gate.waitForRelease()
        } onCancel: { [gate] in
            Task { await gate.observeCancellation() }
        }
        try Task.checkCancellation()
    }

    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> String {
        try await blockUntilReleasedOrCancelled()
        // Production now compares this source digest against the real
        // destination digest read through the pinned handle, so this must
        // be the file's actual checksum rather than a fixed placeholder.
        return try await SharedChecksumService.shared.generateChecksum(
            for: fileURL,
            type: type,
            useCache: false,
            progressCallback: nil
        )
    }

    func verifyFileIntegrity(
        sourceURL: URL,
        destinationURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback?
    ) async throws -> VerificationResult {
        try await blockUntilReleasedOrCancelled()
        return VerificationResult(
            sourceChecksum: "hash",
            destinationChecksum: "hash",
            matches: true,
            checksumType: type,
            processingTime: 0,
            fileSize: 17
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

private final class BlockingFailureFileSystem: FileSystemService, @unchecked Sendable {
    private let base = MacOSFileSystemService.shared
    private let failingPath: String
    private let condition = NSCondition()
    private var entered = false
    private var released = false

    init(failingDirectory: URL) {
        failingPath = failingDirectory.standardizedFileURL.path
    }

    var didEnterFailingDirectory: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    func releaseFailingDirectory() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func selectSourceFolder() async -> URL? { nil }
    func selectDestinationFolders() async -> [URL] { [] }
    func selectLeftFolder() async -> URL? { nil }
    func selectRightFolder() async -> URL? { nil }
    func validateFileAccess(url: URL) async -> Bool { true }
    func startAccessing(url: URL) -> Bool { true }
    func stopAccessing(url: URL) {}
    func getFileList(from folderURL: URL) async throws -> [URL] { try await base.getFileList(from: folderURL) }
    nonisolated func getFileSize(for url: URL) throws -> Int64 { try base.getFileSize(for: url) }

    nonisolated func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    /// Blocks the caller until released, then fails, simulating a destination
    /// whose setup hangs and then errors out.
    nonisolated func enterFailingDirectory() throws {
        condition.lock()
        entered = true
        condition.broadcast()
        while !released { condition.wait() }
        condition.unlock()
        throw NSError(domain: "OperationOwnershipTests", code: 41)
    }

    nonisolated func freeSpace(at url: URL) -> Int64 { .max }
}

private actor AsyncFlag {
    private(set) var value = false
    func set() { value = true }
}

private actor AsyncCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor CoordinatorOperationGate {
    private var count = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var startCount: Int { count }

    func startAndWait() async {
        count += 1
        guard !released else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private final class BlockingFileOperationsService: FileOperationsService, @unchecked Sendable {
    private let gate = CoordinatorOperationGate()

    var startCount: Int { get async { await gate.startCount } }
    func release() async { await gate.release() }

    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64?,
        progressCallback: @escaping ProgressCallback,
        onFileResult: FileResultCallback?
    ) async throws -> FileOperation {
        await gate.startAndWait()
        return FileOperation(
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

private final class OwnershipPlatformManager: PlatformManager {
    nonisolated let fileSystem: FileSystemService = OwnershipFileSystem()
    nonisolated let checksum: ChecksumService = OwnershipChecksumService()
    nonisolated let fileOperations: FileOperationsService
    nonisolated let cameraDetection: CameraDetectionService = OwnershipCameraDetectionService()
    nonisolated let supportsDragAndDrop = false

    init(fileOperations: FileOperationsService) {
        self.fileOperations = fileOperations
    }

    func presentAlert(title: String, message: String) async {}
    func presentError(_ error: Error) async {}
    func openURL(_ url: URL) async -> Bool { false }
}

private final class OwnershipFileSystem: FileSystemService {
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

private final class OwnershipChecksumService: ChecksumService {
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

private final class OwnershipCameraDetectionService: CameraDetectionService {
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

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task<Never, Never>.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}
