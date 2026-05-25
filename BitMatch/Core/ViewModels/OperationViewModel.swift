// Core/ViewModels/OperationViewModel.swift - Refactored to use focused services
import Foundation
import SwiftUI
import Combine
import UserNotifications
import AppKit

@MainActor
final class OperationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var state: OperationState = .idle
    @Published var results: [ResultRow] = []
    @Published var verificationMode: VerificationMode = .standard
    
    // MHL Generation tracking
    @Published var mhlGenerated = false
    @Published var mhlFilePath: String?
    @Published var isGeneratingMHL = false

    // Error display
    @Published var showError = false
    @Published var errorMessage: String?
    
    // Memory management
    private let maxResultsInMemory = 10_000
    private var resultsOverflowFile: URL?
    private let mhlCollectorActor = MHLOperationService.MHLCollectorActor()
    
    // Observable changes for UI updates
    var statePublisher: AnyPublisher<OperationState, Never> {
        $state.eraseToAnyPublisher()
    }
    
    // MARK: - Computed Properties
    var isVerifying: Bool { state.isActive }
    var isPaused: Bool { state.isPaused }
    var canCancel: Bool { state.canCancel }
    
    var completionState: CompletionState {
        switch state {
        case .idle, .notStarted: 
            return .idle
        case .inProgress, .copying, .verifying, .paused, .resuming: 
            return .inProgress
        case .completed(let info):
            return info.success ? .success(message: info.message) : .issues(message: info.message)
        case .failed:
            return .failed(message: "Operation failed")
        case .cancelled:
            return .failed(message: "Operation was cancelled")
        }
    }
    
    // MARK: - Private Properties
    private var operationTask: Task<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var jobID = UUID()
    private var jobStart = Date()
    
    private var activeDestinations: [URL] = []
    private var currentMode: AppMode {
        return fileSelectionViewModel.sourceURL != nil ? .copyAndVerify : .compareFolders
    }
    
    // MARK: - Dependencies
    private let progressViewModel: ProgressViewModel
    private let fileSelectionViewModel: FileSelectionViewModel
    private let cameraLabelViewModel: CameraLabelViewModel
    private let settingsViewModel: SettingsViewModel
    
    // MARK: - Initialization
    init(progressViewModel: ProgressViewModel,
         fileSelectionViewModel: FileSelectionViewModel,
         cameraLabelViewModel: CameraLabelViewModel,
         settingsViewModel: SettingsViewModel) {
        self.progressViewModel = progressViewModel
        self.fileSelectionViewModel = fileSelectionViewModel
        self.cameraLabelViewModel = cameraLabelViewModel
        self.settingsViewModel = settingsViewModel
        
        // Check for interrupted operations on init
        OperationResumeService.checkForInterruptedOperations { [weak self] operation in
            self?.resumeOperation(operation)
        }
    }
    
    // MARK: - Public Methods
    
    func resetCompletionState() {
        if case .completed = state {
            state = .idle
        }
        isGeneratingMHL = false
    }
    
    func startComparison() {
        guard let left = fileSelectionViewModel.leftURL,
              let right = fileSelectionViewModel.rightURL else { return }
        
        activeDestinations = [right]
        prepareForOperation()
        
        operationTask = Task {
            do {
                state = .verifying
                
                try await ComparisonOperationService.performComparison(
                    left: left,
                    right: right,
                    verificationMode: verificationMode,
                    progressViewModel: progressViewModel,
                    onProgress: { [weak self] newResults in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.addResults(newResults)
                        }
                    },
                    onComplete: { [weak self] in
                        Task { @MainActor [weak self] in
                            await self?.handleOperationComplete()
                        }
                    },
                    shouldGenerateMHL: MHLOperationService.shouldGenerateMHL(for: verificationMode),
                    mhlCollector: verificationMode.requiresMHL ? mhlCollectorActor : nil
                )
                
            } catch is CancellationError {
                // User cancelled the operation; do not surface as an error state
                return
            } catch {
                await handleOperationError(error)
            }
        }
    }
    
    func startCopyAndVerify() {
        guard let source = fileSelectionViewModel.sourceURL,
              !fileSelectionViewModel.destinationURLs.isEmpty else { return }

        // Validate destinations are safe before any destination folders are created.
        let validDestinations = fileSelectionViewModel.validateDestinations(for: source)
        let invalidCount = fileSelectionViewModel.destinationURLs.count - validDestinations.count

        if invalidCount > 0 {
            let destinationPathCounts = Dictionary(
                grouping: fileSelectionViewModel.destinationURLs,
                by: { $0.standardizedFileURL.resolvingSymlinksInPath().path }
            ).mapValues(\.count)
            let invalidReasons = fileSelectionViewModel.destinationURLs.compactMap { dest -> String? in
                let path = dest.standardizedFileURL.resolvingSymlinksInPath().path
                if (destinationPathCounts[path] ?? 0) > 1 {
                    return "\(dest.lastPathComponent): Destination is already selected"
                }
                if SafetyValidator.isProtectedSystemPath(dest) {
                    return "\(dest.lastPathComponent): System folders cannot be used as destinations"
                }
                if let reason = SafetyValidator.destinationSafetyIssue(source: source, destination: dest) {
                    return "\(dest.lastPathComponent): \(reason)"
                }
                return "\(dest.lastPathComponent): Destination is not safe for this transfer"
            }
            errorMessage = "Cannot start transfer. \(invalidReasons.joined(separator: "; "))"
            showError = true
            return
        }

        activeDestinations = validDestinations
        prepareForOperation()
        let cameraSettings = cameraLabelViewModel.destinationLabelSettings
        // Configure planned total bytes for bytes-based ETA (source size × destinations)
        // Use safe multiplication to prevent overflow on large multi-destination copies
        if let totalSize = fileSelectionViewModel.sourceFolderInfo?.totalSize {
            let destCount = Int64(max(1, fileSelectionViewModel.destinationURLs.count))
            let maxSafeSize = Int64.max / destCount
            let safeSourceSize = min(Int64(totalSize), maxSafeSize)
            let total = safeSourceSize * destCount
            progressViewModel.setPlannedTotalBytes(total)
        } else {
            progressViewModel.setPlannedTotalBytes(nil)
        }
        
        operationTask = Task {
            do {
                state = .copying
                
                try await ComparisonOperationService.performCopyAndVerify(
                    source: source,
                    destinations: fileSelectionViewModel.destinationURLs,
                    verificationMode: verificationMode,
                    cameraLabelSettings: cameraSettings,
                    progressViewModel: progressViewModel,
                    onProgress: { [weak self] newResults in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.addResults(newResults)
                        }
                    },
                    onComplete: { [weak self] in
                        Task { @MainActor [weak self] in
                            await self?.handleOperationComplete()
                        }
                    },
                    shouldGenerateMHL: MHLOperationService.shouldGenerateMHL(for: verificationMode),
                    mhlCollector: verificationMode.requiresMHL ? mhlCollectorActor : nil
                )
            } catch is CancellationError {
                return
            } catch {
                await handleOperationError(error)
            }
        }
    }
    
    func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
        activeDestinations = []
        
        // Resume paused task if any
        pauseContinuation?.resume()
        pauseContinuation = nil
        
        Task {
            await cleanupAfterOperation()
            await MainActor.run {
                state = .idle
                progressViewModel.reset()
                // Stop progress interpolation timer on cancel
                progressViewModel.stopProgressTracking()
            }
        }
    }
    
    func togglePause() {
        // Implement cooperative pause by cancelling tasks and saving a checkpoint
        guard state.isActive else { return }
        let filesProcessed = progressViewModel.fileCountCompleted
        let totalFiles = max(progressViewModel.fileCountTotal, filesProcessed)
        let lastFile = progressViewModel.currentFileName ?? "unknown"

        // Save checkpoint for resume UI
        OperationStateManager.createCheckpoint(
            for: jobID,
            filesProcessed: filesProcessed,
            lastFile: lastFile
        )

        // Transition to paused state for UI
        state = .paused(PauseInfo(
            pausedAt: Date(),
            currentFile: progressViewModel.currentFileName,
            filesProcessed: filesProcessed,
            totalFiles: totalFiles,
            bytesProcessed: progressViewModel.getTotalBytesProcessed(),
            reason: .userRequested
        ))

        // Cancel current tasks; resume will restart and reuse only files that can be verified.
        operationTask?.cancel()
        operationTask = nil
        // Resume paused continuation if any to unblock waits
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
    
    func resumeOperation(_ operation: OperationStateManager.PersistedOperation) {
        let (newJobID, newJobStart) = OperationResumeService.prepareResumeData(
            operation: operation,
            fileSelectionViewModel: fileSelectionViewModel,
            progressViewModel: progressViewModel,
            verificationMode: &verificationMode
        )
        
        jobID = newJobID
        jobStart = newJobStart
        
        // Restart the operation (actual resume logic would need more implementation)
        if operation.mode == "copy" {
            startCopyAndVerify()
        } else {
            startComparison()
        }
    }
    
    // MARK: - Private Methods
    
    private func prepareForOperation() {
        results.removeAll()
        results.reserveCapacity(min(1000, maxResultsInMemory))
        resultsOverflowFile = nil

        jobID = UUID()
        jobStart = Date()
        progressViewModel.reset()

        Task { [weak self] in
            await self?.mhlCollectorActor.clear()
        }
        mhlGenerated = false
        mhlFilePath = nil
        isGeneratingMHL = false

        let initialOperation = OperationStateManager.PersistedOperation(
            id: jobID,
            startTime: jobStart,
            mode: currentMode == .copyAndVerify ? "copy" : "compare",
            sourceURL: fileSelectionViewModel.sourceURL ?? fileSelectionViewModel.leftURL ?? URL(fileURLWithPath: "/"),
            destinationURLs: currentMode == .copyAndVerify
                ? fileSelectionViewModel.destinationURLs
                : [fileSelectionViewModel.rightURL].compactMap { $0 },
            verificationMode: verificationMode.rawValue,
            lastProcessedFile: "Starting...",
            processedCount: 0,
            totalCount: 0,
            checkpoints: []
        )
        OperationStateManager.saveState(initialOperation)
        
        state = .idle
        // Future enhancement: implement operation queue for multiple pending tasks
        // Task {
        //     await operationQueue.reset()
        // }
    }
    
    private func handleOperationComplete() async {
        // Generate MHL if needed
        if verificationMode.requiresMHL {
            await generateMHLIfNeeded()
        }

        let finishedAt = Date()
        let exportContext = makeReportExportContext(finishedAt: finishedAt)

        await cleanupAfterOperation()

        // Determine completion status
        let hasIssues = results.contains { !($0.status.contains("✅") || $0.status.contains("Match")) }
        var message = hasIssues ? "Completed with issues" : "All files verified successfully"
        let reused = progressViewModel.reusedFileCopies
        if reused > 0 {
            message += " (Reused \(reused) copies)"
        }
        let _ = results.filter { $0.status.contains("✅") || $0.status.contains("Match") }.count
        let _ = results.filter { !($0.status.contains("✅") || $0.status.contains("Match")) }.count
        let _ = Date().timeIntervalSince(jobStart)

        // Stop progress interpolation timer
        progressViewModel.stopProgressTracking()

        if let context = exportContext {
            Task.detached(priority: .utility) {
                await ReportExporter.export(
                    mode: context.mode,
                    jobID: context.jobID,
                    started: context.started,
                    finished: context.finished,
                    sourceURL: context.source,
                    destinationURLs: context.destinations,
                    results: context.results,
                    fileCount: context.fileCount,
                    matchCount: context.matchCount,
                    prefs: context.prefs,
                    workers: context.workers,
                    totalBytesProcessed: context.totalBytes,
                    generateFullReport: context.generateFullReport
                )
            }
        } else {
            NSLog("Report export skipped: unable to build export context (mode=\(currentMode), source=\(String(describing: fileSelectionViewModel.sourceURL)), destinations=\(fileSelectionViewModel.destinationURLs))")
        }

        state = .completed(OperationCompletionInfo(
            success: !hasIssues,
            message: message
        ))
        sendCompletionNotification(success: !hasIssues, message: message)
    }
    
    private func handleOperationError(_ error: Error) async {
        // Treat cancellation as a non-error and return to idle without showing a failure page
        if error is CancellationError {
            await MainActor.run {
                state = .idle
            }
            return
        }
        await cleanupAfterOperation()
        let _ = results.filter { $0.status.contains("✅") || $0.status.contains("Match") }.count
        let _ = results.filter { !($0.status.contains("✅") || $0.status.contains("Match")) }.count
        let _ = Date().timeIntervalSince(jobStart)

        // Stop progress interpolation timer on error
        progressViewModel.stopProgressTracking()

        let errorMessage = "Operation failed: \(error.localizedDescription)"
        state = .completed(OperationCompletionInfo(
            success: false,
            message: errorMessage
        ))
        sendCompletionNotification(success: false, message: errorMessage)
    }

    // MARK: - Shared Core Integration Helpers
    /// Allow mac adapter to update visible state based on shared coordinator events.
    func setActiveStateFromShared() {
        if case .inProgress = state { return }
        state = .inProgress
    }

    func setCompletionFromShared(success: Bool, message: String) {
        // Stop interpolation timer to avoid UI drift
        progressViewModel.stopProgressTracking()
        state = .completed(OperationCompletionInfo(success: success, message: message))
        sendCompletionNotification(success: success, message: message)
    }

    func setFailedFromShared(message: String = "Operation failed") {
        progressViewModel.stopProgressTracking()
        state = .failed
    }

    func setCancelledFromShared() {
        // Treat cancel as returning to idle selection screen
        progressViewModel.stopProgressTracking()
        state = .idle
    }

    /// Update state based on shared progress stage to drive mac UI labels/bars
    func applyStageFromShared(_ stage: ProgressStage) {
        switch stage {
        case .copying:
            state = .copying
        case .verifying:
            state = .verifying
        case .completed:
            break
        default:
            if state == .idle || state == .notStarted { state = .inProgress }
        }
    }
    
    private struct ReportExportContext {
        let mode: AppMode
        let jobID: UUID
        let started: Date
        let finished: Date
        let source: URL
        let destinations: [URL]
        let results: [ResultRow]
        let fileCount: Int
        let matchCount: Int
        let prefs: ReportPrefs
        let workers: Int
        let totalBytes: Int64
        let generateFullReport: Bool
    }
    
    private func makeReportExportContext(finishedAt: Date) -> ReportExportContext? {
        let resultsSnapshot = results
        guard !resultsSnapshot.isEmpty else { return nil }
        
        let mode = currentMode
        guard mode != .masterReport else { return nil }
        
        let sourceURL: URL?
        var destinations: [URL] = []
        
        switch mode {
        case .copyAndVerify:
            sourceURL = fileSelectionViewModel.sourceURL
            destinations = activeDestinations
        case .compareFolders, .masterReport:
            return nil
        }
        
        guard let resolvedSource = sourceURL, !destinations.isEmpty else { return nil }
        
        let matchCount = resultsSnapshot.filter { $0.status.contains("✅") || $0.status.contains("Match") }.count
        let prefsSnapshot = settingsViewModel.prefs
        let totalBytes = progressViewModel.getTotalBytesProcessed()
        let fileCount = resultsSnapshot.count
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)
        
        return ReportExportContext(
            mode: mode,
            jobID: jobID,
            started: jobStart,
            finished: finishedAt,
            source: resolvedSource,
            destinations: destinations,
            results: resultsSnapshot,
            fileCount: fileCount,
            matchCount: matchCount,
            prefs: prefsSnapshot,
            workers: workers,
            totalBytes: totalBytes,
            generateFullReport: prefsSnapshot.makeReport
        )
    }
    
    private func generateMHLIfNeeded() async {
        guard verificationMode.requiresMHL else { return }
        
        let mhlEntries = await mhlCollectorActor.getEntries()
        guard !mhlEntries.isEmpty else { return }
        
        isGeneratingMHL = true
        
        let sourceURL = fileSelectionViewModel.leftURL ?? fileSelectionViewModel.sourceURL ?? URL(fileURLWithPath: "/")
        let destinationURL = fileSelectionViewModel.rightURL ?? fileSelectionViewModel.destinationURLs.first ?? URL(fileURLWithPath: "/")
        
        do {
            let (success, filename) = try await MHLOperationService.generateMHLFile(
                from: mhlEntries,
                source: sourceURL,
                destination: destinationURL,
                algorithm: settingsViewModel.prefs.checksumAlgorithm,
                jobID: jobID,
                jobStart: jobStart,
                settingsViewModel: settingsViewModel,
                onProgress: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.progressViewModel.setProgressMessage(message)
                    }
                }
            )
            
            mhlGenerated = success
            mhlFilePath = filename
            
        } catch {
            SharedLogger.error("Failed to generate MHL: \(error)", category: .transfer)
            progressViewModel.setProgressMessage("MHL generation failed")
        }
        
        isGeneratingMHL = false
    }
    
    private func cleanupAfterOperation() async {
        // Save partial results for potential resume
        savePartialResults()
        activeDestinations = []
    }

    // MARK: - Completion Notification

    private func sendCompletionNotification(success: Bool, message: String) {
        // Play system sound
        if success {
            NSSound(named: "Glass")?.play()
        } else {
            NSSound(named: "Basso")?.play()
        }

        // Send notification (useful when app is in background)
        let content = UNMutableNotificationContent()
        content.title = success ? "Transfer Complete" : "Transfer Failed"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func addResults(_ newResults: [ResultRow]) {
        if results.count + newResults.count > maxResultsInMemory {
            let errors = results.filter { !$0.status.contains("✅") && !$0.status.contains("Match") }
            let keepCount = maxResultsInMemory / 2
            let matchesToKeep = max(0, keepCount - errors.count)
            let matches = results.filter { $0.status.contains("✅") || $0.status.contains("Match") }.suffix(matchesToKeep)
            results = Array(errors + matches)
        }
        results.append(contentsOf: newResults)
    }

    private func savePartialResults() {
        guard results.count > 100 else { return }
        OperationStateManager.createCheckpoint(
            for: jobID,
            filesProcessed: results.count,
            lastFile: results.last?.path ?? "unknown"
        )
    }

}
