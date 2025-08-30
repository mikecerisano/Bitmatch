// Core/ViewModels/OperationViewModel.swift - Refactored to use focused services
import Foundation
import SwiftUI
import Combine

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
        case .completed(let info):
            if info.success {
                return .success(message: info.message)
            } else {
                return .issues(message: info.message)
            }
        default:
            return .idle
        }
    }
    
    // MARK: - Private Properties
    private var operationTask: Task<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private let operationQueue = FileOperationQueue()
    private var jobID = UUID()
    private var jobStart = Date()
    
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
        
        prepareForOperation()
        
        operationTask = Task {
            do {
                state = .verifying(progress: 0, currentFile: "Starting...")
                
                try await ComparisonOperationService.performComparison(
                    left: left,
                    right: right,
                    verificationMode: verificationMode,
                    progressViewModel: progressViewModel,
                    onProgress: { [weak self] newResults in
                        Task { @MainActor in
                            guard let self = self else { return }
                            OperationManager.addResults(newResults, to: &self.results, maxResultsInMemory: self.maxResultsInMemory)
                        }
                    },
                    onComplete: { [weak self] in
                        Task { @MainActor in
                            await self?.handleOperationComplete()
                        }
                    },
                    shouldGenerateMHL: MHLOperationService.shouldGenerateMHL(for: verificationMode),
                    mhlCollector: verificationMode.requiresMHL ? mhlCollectorActor : nil
                )
                
            } catch {
                await handleOperationError(error)
            }
        }
    }
    
    func startCopyAndVerify() {
        guard let source = fileSelectionViewModel.sourceURL,
              !fileSelectionViewModel.destinationURLs.isEmpty else { return }
        
        prepareForOperation()
        
        operationTask = Task {
            do {
                state = .copying(progress: 0, currentFile: "Starting...")
                
                try await ComparisonOperationService.performCopyAndVerify(
                    source: source,
                    destinations: fileSelectionViewModel.destinationURLs,
                    verificationMode: verificationMode,
                    progressViewModel: progressViewModel,
                    onProgress: { [weak self] newResults in
                        Task { @MainActor in
                            guard let self = self else { return }
                            OperationManager.addResults(newResults, to: &self.results, maxResultsInMemory: self.maxResultsInMemory)
                        }
                    },
                    onComplete: { [weak self] in
                        Task { @MainActor in
                            await self?.handleOperationComplete()
                        }
                    },
                    shouldGenerateMHL: MHLOperationService.shouldGenerateMHL(for: verificationMode),
                    mhlCollector: verificationMode.requiresMHL ? mhlCollectorActor : nil
                )
                
            } catch {
                await handleOperationError(error)
            }
        }
    }
    
    func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
        
        // Resume paused task if any
        pauseContinuation?.resume()
        pauseContinuation = nil
        
        Task {
            await cleanupAfterOperation()
            await MainActor.run {
                state = .idle
                progressViewModel.reset()
            }
        }
    }
    
    func togglePause() {
        switch state {
        case .verifying(let progress, _):
            state = .paused(resumeFrom: .verifying(progress: progress))
            
        case .copying(let progress, _):
            state = .paused(resumeFrom: .copying(progress: progress))
            
        case .paused(let phase):
            // Resume operation
            switch phase {
            case .copying(let progress):
                state = .copying(progress: progress, currentFile: progressViewModel.currentFileName)
            case .verifying(let progress):
                state = .verifying(progress: progress, currentFile: progressViewModel.currentFileName)
            }
            pauseContinuation?.resume()
            pauseContinuation = nil
            
        default:
            break
        }
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
        OperationManager.prepareForOperation(
            jobID: &jobID,
            jobStart: &jobStart,
            currentMode: currentMode,
            fileSelectionViewModel: fileSelectionViewModel,
            progressViewModel: progressViewModel,
            verificationMode: verificationMode,
            onClearResults: { [weak self] in
                self?.results.removeAll()
                self?.results.reserveCapacity(min(1000, self?.maxResultsInMemory ?? 10_000))
                self?.resultsOverflowFile = nil
            },
            onClearMHL: { [weak self] in
                Task {
                    await self?.mhlCollectorActor.clear()
                }
                self?.mhlGenerated = false
                self?.mhlFilePath = nil
                self?.isGeneratingMHL = false
            }
        )
        
        state = .idle
        Task {
            await operationQueue.reset()
        }
    }
    
    private func handleOperationComplete() async {
        // Generate MHL if needed
        if verificationMode.requiresMHL {
            await generateMHLIfNeeded()
        }
        
        await cleanupAfterOperation()
        
        // Determine completion status
        let hasIssues = results.contains { $0.status != .match }
        let message = hasIssues ? "Completed with issues" : "All files verified successfully"
        let matchCount = results.filter { $0.status == .match }.count
        let issueCount = results.filter { $0.status != .match }.count
        let duration = Date().timeIntervalSince(jobStart)
        
        state = .completed(OperationState.CompletionInfo(
            success: !hasIssues, 
            message: message, 
            fileCount: results.count, 
            matchCount: matchCount, 
            issueCount: issueCount, 
            duration: duration
        ))
    }
    
    private func handleOperationError(_ error: Error) async {
        await cleanupAfterOperation()
        let matchCount = results.filter { $0.status == .match }.count
        let issueCount = results.filter { $0.status != .match }.count
        let duration = Date().timeIntervalSince(jobStart)
        
        state = .completed(OperationState.CompletionInfo(
            success: false, 
            message: "Operation failed: \(error.localizedDescription)", 
            fileCount: results.count, 
            matchCount: matchCount, 
            issueCount: issueCount, 
            duration: duration
        ))
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
                onProgress: { message in
                    Task { @MainActor in
                        self.progressViewModel.setProgressMessage(message)
                    }
                }
            )
            
            mhlGenerated = success
            mhlFilePath = filename
            
        } catch {
            print("Failed to generate MHL: \(error)")
            progressViewModel.setProgressMessage("MHL generation failed")
        }
        
        isGeneratingMHL = false
    }
    
    private func cleanupAfterOperation() async {
        // Clean up temporary files
        var urlsToClean: [URL] = []
        
        if let source = fileSelectionViewModel.sourceURL {
            urlsToClean.append(source)
        }
        if let left = fileSelectionViewModel.leftURL {
            urlsToClean.append(left)
        }
        if let right = fileSelectionViewModel.rightURL {
            urlsToClean.append(right)
        }
        urlsToClean.append(contentsOf: fileSelectionViewModel.destinationURLs)
        
        await OperationManager.cleanupTemporaryFiles(at: urlsToClean)
        
        // Save partial results for potential resume
        OperationManager.savePartialResults(results, jobID: jobID)
    }
}