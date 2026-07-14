// CopyVerifyExecutor.swift - Handles copy and verify operation execution
import Foundation

typealias PhotographerReportFinalizer = @MainActor ([ResultRow]) throws -> PhotographerReportContext?

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
    let photographerReportFinalizer: PhotographerReportFinalizer?

    init(
        operationId: UUID,
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        cameraLabelSettings: CameraLabelSettings,
        reportSettings: ReportPrefs,
        estimatedFiles: Int,
        estimatedBytes: Int64,
        currentMode: AppMode,
        photographerReportFinalizer: PhotographerReportFinalizer? = nil
    ) {
        self.operationId = operationId
        self.sourceURL = sourceURL
        self.destinationURLs = destinationURLs
        self.verificationMode = verificationMode
        self.cameraLabelSettings = cameraLabelSettings
        self.reportSettings = reportSettings
        self.estimatedFiles = estimatedFiles
        self.estimatedBytes = estimatedBytes
        self.currentMode = currentMode
        self.photographerReportFinalizer = photographerReportFinalizer
    }
}

/// Callbacks for operation progress and results
struct CopyVerifyCallbacks {
    let onProgress: @MainActor (OperationProgress) -> Void
    let onResult: @MainActor (ResultRow) -> Void
    let onStateChange: @MainActor (OperationState) -> Void
    let onAuthoritativeResults: @MainActor ([ResultRow]) throws -> Void
}

/// Service that executes copy/verify operations
/// Extracted from SharedAppCoordinator to reduce its size
@MainActor
final class CopyVerifyExecutor {

    struct PhotographerLifecycleFinalization {
        let context: PhotographerReportContext?
        let didPersist: Bool
    }

    // MARK: - Dependencies
    private let platformManager: PlatformManager
    private let timingService: OperationTimingService
    private let errorService: ErrorReportingService
    private let stateService: OperationStateService
    private let backgroundTaskService: IOSBackgroundTaskService

    // MARK: - State
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
        let overflowService = ResultsOverflowService(
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
                guard let self else { return }
                await self.handleFileResult(
                    fileResult,
                    overflowService: overflowService,
                    callbacks: callbacks
                )
            }

            return try await handleSuccess(
                operation: operation,
                overflowService: overflowService,
                config: config,
                callbacks: callbacks
            )

        } catch {
            await handleError(
                error,
                overflowService: overflowService,
                config: config,
                callbacks: callbacks
            )
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

    private func handleFileResult(
        _ fileResult: FileOperationResult,
        overflowService: ResultsOverflowService,
        callbacks: CopyVerifyCallbacks
    ) async {
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

        // Use overflow service for large transfers. Single atomic call:
        // copy and verify rows can arrive out of order, and the store
        // refuses to let a copy row replace a verify result.
        await overflowService.upsert(resultRow)

        callbacks.onResult(resultRow)
    }

    // MARK: - Completion Handling

    private func handleSuccess(
        operation: FileOperation,
        overflowService: ResultsOverflowService,
        config: CopyVerifyConfig,
        callbacks: CopyVerifyCallbacks
    ) async throws -> FileOperation {
        let allResults = operation.results.map { fileResult in
            ResultRow(
                path: fileResult.sourceURL.path,
                status: fileResult.statusDescription,
                size: fileResult.fileSize,
                checksum: fileResult.verificationResult?.sourceChecksum,
                destination: driveName(for: fileResult.destinationURL),
                destinationPath: fileResult.destinationURL.path
            )
        }
        SharedLogger.info("Mapped \(allResults.count) authoritative operation results for report", category: .transfer)

        let issueCount = allResults.filter { !$0.isSuccessStatus }.count
        let fileResultsSucceeded = issueCount == 0
        let fileResultsMessage = fileResultsSucceeded ?
            "Operation completed successfully" :
            "Operation completed with \(issueCount) issue\(issueCount == 1 ? "" : "s")"

        let photographerLifecycle = try Self.photographerLifecycleAfterAuthoritativeCompletion(
            completion: {
                try callbacks.onAuthoritativeResults(allResults)
                guard let finalizer = config.photographerReportFinalizer else { return nil }
                return try finalizer(allResults)
            }
        )
        let succeeded = fileResultsSucceeded && photographerLifecycle.didPersist
        let completionMessage = photographerLifecycle.didPersist
            ? fileResultsMessage
            : "\(fileResultsMessage); photographer lifecycle finalization failed"

        timingService.completeOperation(success: succeeded, message: completionMessage)
        errorService.completeErrorTracking()
        stateService.completeOperation()

        // Generate report if enabled
        if config.reportSettings.makeReport && !allResults.isEmpty {
            await generateReport(
                operation: operation,
                results: allResults,
                config: config,
                photographerContext: photographerLifecycle.context
            )
        }

        callbacks.onStateChange(.completed(OperationCompletionInfo(success: succeeded, message: completionMessage)))

        // Clean up
        await cleanupOverflowService(overflowService)

        SharedLogger.info("CopyVerifyExecutor: operation completed", category: .transfer)
        NotificationCenter.default.post(name: .operationCompleted, object: nil)

        return operation
    }

    private func handleError(
        _ error: Error,
        overflowService: ResultsOverflowService,
        config: CopyVerifyConfig,
        callbacks: CopyVerifyCallbacks
    ) async {
        await cleanupOverflowService(overflowService)

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
        config: CopyVerifyConfig,
        photographerContext: PhotographerReportContext?
    ) async {
        let matchCount = results.filter { $0.isSuccessStatus }.count
        let totalBytesProcessed = config.estimatedBytes
        let fileCount = results.count
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)

        SharedLogger.info("Auto-report queued for job \(operation.id) with \(fileCount) rows", category: .transfer)

        #if os(macOS)
        let reportMode = config.currentMode
        let reportSettings = config.reportSettings
        let reportResults = results
        let reportOperation = operation
        let reportContext = photographerContext

        Task.detached(priority: .utility) {
            await ReportExporter.export(
                mode: reportMode,
                jobID: reportOperation.id,
                started: reportOperation.startTime,
                finished: reportOperation.endTime ?? Date(),
                sourceURL: reportOperation.sourceURL,
                destinationURLs: reportOperation.destinationURLs,
                results: reportResults,
                fileCount: fileCount,
                matchCount: matchCount,
                prefs: reportSettings,
                workers: workers,
                totalBytesProcessed: totalBytesProcessed,
                generateFullReport: reportSettings.makeReport,
                photographerContext: reportContext
            )
        }
        #else
        SharedLogger.info("Report export not available on iOS", category: .transfer)
        #endif
    }

    static func photographerLifecycleAfterAuthoritativeCompletion(
        completion: @MainActor () throws -> PhotographerReportContext?
    ) throws -> PhotographerLifecycleFinalization {
        do {
            let context = try completion()
            return PhotographerLifecycleFinalization(
                context: context,
                didPersist: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            SharedLogger.error(
                "Photographer lifecycle finalization failed; exporting without photographer context: \(error.localizedDescription)",
                category: .transfer
            )
            return PhotographerLifecycleFinalization(context: nil, didPersist: false)
        }
    }

    // MARK: - Helpers

    private func cleanupOverflowService(_ overflowService: ResultsOverflowService) async {
        await overflowService.clear()
    }

    private func driveName(for url: URL) -> String {
        let comps = url.pathComponents
        if let volIndex = comps.firstIndex(of: "Volumes"), volIndex + 1 < comps.count {
            return comps[volIndex + 1]
        }
        return url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }

    /// Cancel the current operation
    func cancel() {
        platformManager.fileOperations.cancelOperation()
        timingService.cancelOperation()
    }
}
