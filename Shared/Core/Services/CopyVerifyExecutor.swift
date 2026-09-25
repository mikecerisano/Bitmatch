// CopyVerifyExecutor.swift - Handles copy and verify operation execution
import Foundation

struct PhotographerFinalizationResult {
    /// The post-persistence context used to retain photographer provenance in
    /// reports, including reports for cards that did not become locally safe.
    let context: PhotographerReportContext?
    /// The persisted card verdict. A configured photographer finalizer must
    /// explicitly certify this before raw copy rows can complete successfully.
    let locallySafe: Bool
}

typealias PhotographerReportFinalizer = @MainActor ([ResultRow]) throws -> PhotographerFinalizationResult

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
    let generateASCMHL: Bool

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
        photographerReportFinalizer: PhotographerReportFinalizer? = nil,
        generateASCMHL: Bool = false
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
        self.generateASCMHL = generateASCMHL
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
        /// `nil` means no photographer finalizer was configured for this
        /// ordinary copy. A configured finalizer must return `true`.
        let locallySafe: Bool?

        var permitsSuccessfulCompletion: Bool {
            didPersist && (locallySafe ?? true)
        }
    }

    // MARK: - Dependencies
    private let platformManager: PlatformManager
    private let timingService: OperationTimingService
    private let errorService: ErrorReportingService
    private let stateService: OperationStateService
    private let backgroundTaskService: IOSBackgroundTaskService
    private let sleepPreventer: TransferSleepPreventing

    // MARK: - State
    private var handoffTask: Task<[String], Error>?
    private var reportTask: Task<Void, Error>?
    private var cancellationRequested = false
    private var destinationRoots: [URL] = []

    // MARK: - Initialization

    init(
        platformManager: PlatformManager,
        timingService: OperationTimingService,
        errorService: ErrorReportingService,
        stateService: OperationStateService,
        backgroundTaskService: IOSBackgroundTaskService,
        sleepPreventer: TransferSleepPreventing = ProcessInfoSleepPreventer()
    ) {
        self.platformManager = platformManager
        self.timingService = timingService
        self.errorService = errorService
        self.stateService = stateService
        self.backgroundTaskService = backgroundTaskService
        self.sleepPreventer = sleepPreventer
    }

    // MARK: - Execution

    /// Execute a copy and verify operation
    /// Returns the final results array
    func execute(
        config: CopyVerifyConfig,
        callbacks: CopyVerifyCallbacks
    ) async throws -> FileOperation? {
        cancellationRequested = false
        destinationRoots = config.destinationURLs
        SharedLogger.info("CopyVerifyExecutor: starting operation \(config.operationId)", category: .transfer)


        // Start iOS background task
        backgroundTaskService.beginOperation(estimatedFiles: config.estimatedFiles)
        defer { backgroundTaskService.endOperation() }

        // Keep the Mac from idle-sleeping until this operation ends.
        let keepAwake = TransferKeepAwake(preventer: sleepPreventer, reason: "Copying and verifying backups")
        defer { keepAwake.release() }

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
                    callbacks: callbacks
                )
            }

            return try await handleSuccess(
                operation: operation,
                config: config,
                callbacks: callbacks
            )

        } catch {
            // Release before handleError, which can wait on an error alert.
            keepAwake.release()
            await handleError(
                error,
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

        callbacks.onResult(resultRow)
    }

    // MARK: - Completion Handling

    private func handleSuccess(
        operation: FileOperation,
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
        let fileResultsSucceeded = !allResults.isEmpty && issueCount == 0
        let fileResultsMessage = allResults.isEmpty ? "No files were verified" : fileResultsSucceeded ?
            "Operation completed successfully" :
            "Operation completed with \(issueCount) issue\(issueCount == 1 ? "" : "s")"

        let photographerLifecycle = try Self.photographerLifecycleAfterAuthoritativeCompletion(
            completion: {
                try callbacks.onAuthoritativeResults(allResults)
                guard let finalizer = config.photographerReportFinalizer else { return nil }
                return try finalizer(allResults)
            }
        )
        try checkCancellation()
        let handoffIssues = try await createASCMHLHistories(operation: operation, config: config, callbacks: callbacks)
        // A failed requested report is a structured outcome, not a silent side effect:
        // verified media stays described as verified, but completion is issues.
        let reportIssue: String?
        if config.reportSettings.makeReport && !allResults.isEmpty {
            reportIssue = try await generateReport(
                operation: operation,
                results: allResults,
                config: config,
                photographerContext: photographerLifecycle.context,
                handoffSummary: handoffIssues.isEmpty ? nil : handoffIssues.joined(separator: "; ")
            )
        } else {
            reportIssue = nil
        }
        try checkCancellation()
        let succeeded = fileResultsSucceeded && photographerLifecycle.permitsSuccessfulCompletion && handoffIssues.isEmpty && config.verificationMode != .quick && reportIssue == nil
        var completionMessage: String
        if !photographerLifecycle.didPersist {
            completionMessage = "\(fileResultsMessage); photographer lifecycle finalization failed"
        } else if photographerLifecycle.locallySafe == false {
            completionMessage = "\(fileResultsMessage); photographer verification is incomplete"
        } else {
            completionMessage = fileResultsMessage
        }
        if !handoffIssues.isEmpty {
            completionMessage += "; " + handoffIssues.joined(separator: "; ")
        } else if config.generateASCMHL && config.verificationMode != .quick {
            completionMessage += "; ASC MHL handoff records saved"
        }
        if config.verificationMode == .quick {
            completionMessage += "; contents have not been checksum verified."
        }
        if let reportIssue {
            completionMessage += "; report export failed: \(reportIssue)"
        }

        timingService.completeOperation(success: succeeded, message: completionMessage)
        errorService.completeErrorTracking()
        stateService.completeOperation(operationId: config.operationId, success: succeeded, message: completionMessage)

        callbacks.onStateChange(.completed(OperationCompletionInfo(success: succeeded, message: completionMessage)))

        // Clean up
        SharedLogger.info("CopyVerifyExecutor: operation completed", category: .transfer)
        NotificationCenter.default.post(name: .operationCompleted, object: nil)

        return operation
    }

    private func createASCMHLHistories(operation: FileOperation, config: CopyVerifyConfig,
                                       callbacks: CopyVerifyCallbacks) async throws -> [String] {
        guard config.generateASCMHL, config.verificationMode != .quick else { return [] }
        let expectedPaths = Set(operation.results.map { $0.sourceURL.standardizedFileURL.path })
        var jobs: [(URL, [ASCMHLGenerator.VerifiedFile])] = []
        var issues: [String] = []
        for destination in config.destinationURLs {
            let root: URL
            do {
                root = try SafetyValidator.resolvedDestinationRootChecked(
                    source: config.sourceURL, destination: destination, settings: config.cameraLabelSettings
                )
            } catch {
                issues.append("\(destination.lastPathComponent): ASC MHL not created — \(error.localizedDescription)")
                continue
            }
            let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            let rows = operation.results.filter { canonicalRoot.isAncestor(of: $0.destinationURL.standardizedFileURL.resolvingSymlinksInPath()) }
            guard !expectedPaths.isEmpty, rows.count == expectedPaths.count,
                  Set(rows.map { $0.sourceURL.standardizedFileURL.path }) == expectedPaths,
                  rows.allSatisfy({ $0.success && $0.verificationResult?.isValid == true && $0.verificationResult?.checksumType == .sha256 }) else {
                issues.append("\(destination.lastPathComponent): ASC MHL not created because verification is incomplete")
                continue
            }
            jobs.append((root, rows.map {
                ASCMHLGenerator.VerifiedFile(
                    relativePath: $0.destinationURL.standardizedFileURL.resolvingSymlinksInPath().relativePath(to: canonicalRoot),
                    size: $0.fileSize, expectedSHA256: $0.verificationResult?.sourceChecksum ?? ""
                )
            }))
        }
        callbacks.onStateChange(.verifying)
        timingService.updateStage(.verifying)
        stateService.updateCapabilities(canPause: false, canResume: false)
        callbacks.onProgress(OperationProgress(
            overallProgress: 1, currentFile: "Creating ASC MHL handoff records…",
            filesProcessed: operation.results.count, totalFiles: operation.results.count,
            currentStage: .verifying, speed: nil, timeRemaining: nil
        ))
        let sourceURL = config.sourceURL
        let startTime = operation.startTime
        let work = Task.detached(priority: .utility) { [jobs, issues] () throws -> [String] in
            var failures = issues
            for (root, files) in jobs {
                try Task.checkCancellation()
                do {
                    _ = try ASCMHLGenerator.generateInitialHistory(destinationURL: root, files: files, startTime: startTime, sourceURL: sourceURL)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append("\(root.lastPathComponent): ASC MHL — \(error.localizedDescription)")
                }
            }
            return failures
        }
        handoffTask = work
        defer { handoffTask = nil }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }

    private func handleError(
        _ error: Error,
        config: CopyVerifyConfig,
        callbacks: CopyVerifyCallbacks
    ) async {
        if error is CancellationError {
            timingService.cancelOperation()
            errorService.completeErrorTracking()
            stateService.cancelOperation(operationId: config.operationId)
            callbacks.onStateChange(.cancelled)
        } else {
            let context = ErrorContext.general(operation: "File Operation", stage: "Execution")
            errorService.reportError(error, context: context)
            timingService.completeOperation(success: false, message: error.localizedDescription)
            errorService.completeErrorTracking()
            stateService.failOperation(operationId: config.operationId)
            callbacks.onStateChange(.failed)
            await platformManager.presentError(error)
        }

        SharedLogger.info("CopyVerifyExecutor: operation ended with error", category: .transfer)
    }

    // MARK: - Report Generation

    /// Runs the requested automatic report export. Returns nil on success or a
    /// human-readable failure carried into the completion message, the journal
    /// record, and the queue decision — never a silent alert.
    private func generateReport(
        operation: FileOperation,
        results: [ResultRow],
        config: CopyVerifyConfig,
        photographerContext: PhotographerReportContext?,
        handoffSummary: String? = nil
    ) async throws -> String? {
        try checkCancellation()
        // Matches are verified files only; a Quick copy is not a match.
        let matchCount = results.filter { TransferOutcomePresentation.isVerified($0) }.count
        // Evidence (Promise 3): bytes actually copied, one row per file per
        // backup. config.estimatedBytes is a progress estimate that falls
        // back to a placeholder when the source was not measured.
        let totalBytesProcessed = results.reduce(Int64(0)) { $0 + $1.size }
        let fileCount = results.count
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)

        SharedLogger.info("Auto-report queued for job \(operation.id) with \(fileCount) rows", category: .transfer)

        let reportMode = config.currentMode
        var reportSettings = config.reportSettings
        reportSettings.verificationMode = config.verificationMode
        if let handoffSummary { reportSettings.notes += "\nASC MHL: \(handoffSummary)" }
        let reportResults = results
        let reportOperation = operation
        let reportContext = photographerContext

        let work = Task.detached(priority: .utility) {
            try await ReportExporter.export(
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
        reportTask = work
        defer { reportTask = nil }
        do {
            try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try checkCancellation()
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try checkCancellation()
            SharedLogger.error("Auto-report failed for job \(operation.id): \(error.localizedDescription)", category: .transfer)
            return error.localizedDescription
        }
    }

    static func photographerLifecycleAfterAuthoritativeCompletion(
        completion: @MainActor () throws -> PhotographerFinalizationResult?
    ) throws -> PhotographerLifecycleFinalization {
        do {
            let result = try completion()
            return PhotographerLifecycleFinalization(
                context: result?.context,
                didPersist: true,
                locallySafe: result?.locallySafe
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            SharedLogger.error(
                "Photographer lifecycle finalization failed; exporting without photographer context: \(error.localizedDescription)",
                category: .transfer
            )
            return PhotographerLifecycleFinalization(context: nil, didPersist: false, locallySafe: nil)
        }
    }

    // MARK: - Helpers

    private func driveName(for url: URL) -> String {
        Self.destinationLabel(for: url, roots: destinationRoots)
    }

    /// The backup a written file belongs to, as reports name it: the drive
    /// under /Volumes, otherwise the chosen backup folder. `/var` and
    /// `/private/var` spellings agree (see `ResultPathMatch`).
    nonisolated static func destinationLabel(for file: URL, roots: [URL]) -> String {
        let filePath = ResultPathMatch.comparablePath(file.path)
        let root = roots
            .map { URL(fileURLWithPath: ResultPathMatch.comparablePath($0.path)) }
            .filter { filePath == $0.path || filePath.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
        let comps = (root ?? file).pathComponents
        if let volIndex = comps.firstIndex(of: "Volumes"), volIndex + 1 < comps.count {
            return comps[volIndex + 1]
        }
        return root?.lastPathComponent ?? file.deletingLastPathComponent().lastPathComponent
    }

    private func checkCancellation() throws {
        if cancellationRequested { throw CancellationError() }
        try Task.checkCancellation()
    }

    /// Cancel the current operation
    func cancel() {
        cancellationRequested = true
        handoffTask?.cancel()
        reportTask?.cancel()
        platformManager.fileOperations.cancelOperation()
        timingService.cancelOperation()
    }
}
