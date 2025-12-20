// CopyVerifyExecutor.swift - Handles copy and verify operation execution
import Foundation

/// Configuration for a copy/verify operation
struct CopyVerifyConfig {
    let operationId: UUID
    let sourceURL: URL
    let destinationURLs: [URL]
    let verificationMode: VerificationMode
    let cameraLabelSettings: CameraLabelSettings
    let reportSettings: ReportPrefs
    let estimatedFiles: Int
    let estimatedBytes: Int64
    let currentMode: AppMode
}

/// Callbacks for operation progress and results
struct CopyVerifyCallbacks {
    let onProgress: @MainActor (OperationProgress) -> Void
    let onResult: @MainActor (ResultRow) -> Void
    let onStateChange: @MainActor (OperationState) -> Void
    let onComplete: @MainActor ([ResultRow]) -> Void
}

/// Service that executes copy/verify operations
/// Extracted from SharedAppCoordinator to reduce its size
@MainActor
final class CopyVerifyExecutor {

    // MARK: - Dependencies
    private let platformManager: PlatformManager
    private let timingService: OperationTimingService
    private let errorService: ErrorReportingService
    private let stateService: OperationStateService
    private let backgroundTaskService: IOSBackgroundTaskService

    // MARK: - State
    private var resultsOverflowService: ResultsOverflowService?
    private var currentOperation: FileOperation?
    private let maxResultsInMemory = 5_000

    // MARK: - Initialization

    init(
        platformManager: PlatformManager,
        timingService: OperationTimingService,
        errorService: ErrorReportingService,
        stateService: OperationStateService,
        backgroundTaskService: IOSBackgroundTaskService
    ) {
        self.platformManager = platformManager
        self.timingService = timingService
        self.errorService = errorService
        self.stateService = stateService
        self.backgroundTaskService = backgroundTaskService
    }

    // MARK: - Execution

    /// Execute a copy and verify operation
    /// Returns the final results array
    func execute(
        config: CopyVerifyConfig,
        callbacks: CopyVerifyCallbacks
    ) async throws -> FileOperation? {
        SharedLogger.info("CopyVerifyExecutor: starting operation \(config.operationId)", category: .transfer)

        // Create overflow service for large transfers
        resultsOverflowService = ResultsOverflowService(
            operationId: config.operationId,
            maxInMemoryResults: maxResultsInMemory
        )

        // Start iOS background task
        backgroundTaskService.beginOperation(estimatedFiles: config.estimatedFiles)
        defer { backgroundTaskService.endOperation() }

        // Initialize timing
        timingService.startOperation(totalFiles: config.estimatedFiles, totalBytes: config.estimatedBytes)
        timingService.updateStage(.preparing)

        // Initialize error tracking
        errorService.startErrorTracking(operationId: config.operationId)

        // Initialize state service
        stateService.startOperation(
            id: config.operationId,
            sourceURL: config.sourceURL,
            destinationURLs: config.destinationURLs,
            totalFiles: config.estimatedFiles,
            totalBytes: config.estimatedBytes,
            verificationMode: config.verificationMode.rawValue,
            mode: "copy"
        )
        stateService.updateCapabilities(canPause: true, canResume: false)

        callbacks.onStateChange(stateService.currentState)

        do {
            timingService.updateStage(.copying)

            let operation = try await platformManager.fileOperations.performFileOperation(
                sourceURL: config.sourceURL,
                destinationURLs: config.destinationURLs,
                verificationMode: config.verificationMode,
                settings: config.cameraLabelSettings,
                estimatedTotalBytes: config.estimatedBytes
            ) { [weak self] progressUpdate in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleProgress(progressUpdate, callbacks: callbacks)
                }
            } onFileResult: { [weak self] fileResult in
                Task { @MainActor in
                    guard let self else { return }
                    await self.handleFileResult(fileResult, callbacks: callbacks)
                }
            }

            currentOperation = operation
            return try await handleSuccess(operation: operation, config: config, callbacks: callbacks)

        } catch {
            await handleError(error, config: config, callbacks: callbacks)
            throw error
        }
    }

    // MARK: - Progress Handling

    private func handleProgress(_ progressUpdate: OperationProgress, callbacks: CopyVerifyCallbacks) {
        callbacks.onProgress(progressUpdate)

        // Update timing service
        if let bytesProcessed = progressUpdate.bytesProcessed {
            timingService.updateProgress(
                filesProcessed: progressUpdate.filesProcessed,
                bytesProcessed: bytesProcessed,
                currentFile: progressUpdate.currentFile
            )
        }

        // Update stage if changed
        if progressUpdate.currentStage != timingService.currentTiming?.currentStage {
            timingService.updateStage(progressUpdate.currentStage)
        }

        // Update iOS Live Activity
        backgroundTaskService.updateProgress(progressUpdate)
    }

    private func handleFileResult(_ fileResult: FileOperationResult, callbacks: CopyVerifyCallbacks) async {
        let destName = driveName(for: fileResult.destinationURL)
        let keyPath = fileResult.sourceURL.path

        let resultRow = ResultRow(
            path: keyPath,
            status: fileResult.statusDescription,
            size: fileResult.fileSize,
            checksum: fileResult.verificationResult?.sourceChecksum,
            destination: destName,
            destinationPath: fileResult.destinationURL.path
        )

        // Use overflow service for large transfers
        if let overflowService = resultsOverflowService {
            let didUpdate = await overflowService.updateResult(matching: keyPath, destination: destName, with: resultRow)
            if !didUpdate {
                await overflowService.addResult(resultRow)
            }
        }

        callbacks.onResult(resultRow)
    }

    // MARK: - Completion Handling

    private func handleSuccess(
        operation: FileOperation,
        config: CopyVerifyConfig,
        callbacks: CopyVerifyCallbacks
    ) async throws -> FileOperation {
        timingService.completeOperation(success: true, message: "Operation completed successfully")
        errorService.completeErrorTracking()
        stateService.completeOperation()

        let hasErrors = !errorService.currentErrors.isEmpty
        let completionMessage = hasErrors ?
            "Operation completed with \(errorService.currentErrors.count) issues" :
            "Operation completed successfully"

        callbacks.onStateChange(.completed(OperationCompletionInfo(success: !hasErrors, message: completionMessage)))

        // Get all results for report
        let allResults: [ResultRow]
        if let overflowService = resultsOverflowService {
            allResults = await overflowService.getAllResults()
            SharedLogger.info("Retrieved \(allResults.count) total results for report", category: .transfer)
        } else {
            allResults = operation.results.map { fileResult in
                ResultRow(
                    path: fileResult.sourceURL.path,
                    status: fileResult.statusDescription,
                    size: fileResult.fileSize,
                    checksum: fileResult.verificationResult?.sourceChecksum,
                    destination: driveName(for: fileResult.destinationURL),
                    destinationPath: fileResult.destinationURL.path
                )
            }
        }

        // Generate report if enabled
        if config.reportSettings.makeReport && !allResults.isEmpty {
            await generateReport(
                operation: operation,
                results: allResults,
                config: config
            )
        }

        // Clean up
        await cleanupOverflowService()

        // Notify completion
        callbacks.onComplete(allResults)

        SharedLogger.info("CopyVerifyExecutor: operation completed", category: .transfer)
        NotificationCenter.default.post(name: .operationCompleted, object: nil)

        return operation
    }

    private func handleError(_ error: Error, config: CopyVerifyConfig, callbacks: CopyVerifyCallbacks) async {
        await cleanupOverflowService()

        if error is CancellationError {
            timingService.cancelOperation()
            errorService.completeErrorTracking()
            stateService.cancelOperation()
            callbacks.onStateChange(.cancelled)
        } else {
            let context = ErrorContext.general(operation: "File Operation", stage: "Execution")
            errorService.reportError(error, context: context)
            timingService.completeOperation(success: false, message: error.localizedDescription)
            errorService.completeErrorTracking()
            stateService.cancelOperation()
            callbacks.onStateChange(.failed)
            await platformManager.presentError(error)
        }

        SharedLogger.info("CopyVerifyExecutor: operation ended with error", category: .transfer)
    }

    // MARK: - Report Generation

    private func generateReport(
        operation: FileOperation,
        results: [ResultRow],
        config: CopyVerifyConfig
    ) async {
        let matchCount = results.filter { $0.status.contains("✅") || $0.status.contains("Match") }.count
        let totalBytesProcessed = config.estimatedBytes
        let fileCount = results.count
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)

        SharedLogger.info("Auto-report queued for job \(operation.id) with \(fileCount) rows", category: .transfer)

        #if os(macOS)
        let reportConfig = config
        let reportResults = results
        let reportOperation = operation

        Task.detached(priority: .utility) {
            await ReportExporter.export(
                mode: reportConfig.currentMode,
                jobID: reportOperation.id,
                started: reportOperation.startTime,
                finished: reportOperation.endTime ?? Date(),
                sourceURL: reportOperation.sourceURL,
                destinationURLs: reportOperation.destinationURLs,
                results: reportResults,
                fileCount: fileCount,
                matchCount: matchCount,
                prefs: reportConfig.reportSettings,
                workers: workers,
                totalBytesProcessed: totalBytesProcessed,
                generateFullReport: reportConfig.reportSettings.makeReport
            )
        }
        #else
        SharedLogger.info("Report export not available on iOS", category: .transfer)
        #endif
    }

    // MARK: - Helpers

    private func cleanupOverflowService() async {
        if let overflowService = resultsOverflowService {
            await overflowService.clear()
            resultsOverflowService = nil
        }
    }

    private func driveName(for url: URL) -> String {
        let comps = url.pathComponents
        if let volIndex = comps.firstIndex(of: "Volumes"), volIndex + 1 < comps.count {
            return comps[volIndex + 1]
        }
        return url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }

    /// Get current in-memory results for UI display
    func getCurrentResults() async -> [ResultRow] {
        if let overflowService = resultsOverflowService {
            return await overflowService.currentResults
        }
        return []
    }

    /// Cancel the current operation
    func cancel() {
        platformManager.fileOperations.cancelOperation()
        timingService.cancelOperation()
    }
}
