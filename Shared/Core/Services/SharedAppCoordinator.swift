// SharedAppCoordinator.swift - Platform-agnostic app coordination
import Foundation

// Uses SharedLogger (shared file) for logging across platforms
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#endif

@MainActor
class SharedAppCoordinator: ObservableObject {
    
    // MARK: - Platform Manager
    private let platformManager: PlatformManager
    
    // MARK: - Services
    @Published var timingService = OperationTimingService()
    @Published var errorService = ErrorReportingService()
    @Published var stateService = OperationStateService()
    
    // MARK: - Published State
    @Published var currentMode: AppMode = .copyAndVerify
    @Published var verificationMode: VerificationMode = .standard
    @Published var cameraLabelSettings = CameraLabelSettings()
    @Published var reportSettings = ReportPrefs()
    @Published var photographerJobViewModel: PhotographerJobViewModel
    var photographerReportFinalizer: PhotographerReportFinalizer?

    // MARK: - Operation State
    @Published var isOperationInProgress = false
    @Published var operationState: OperationState = .notStarted
    @Published var progress: OperationProgress?
    @Published var results: [ResultRow] = []
    @Published var currentOperation: FileOperation?

    // MARK: - Sub-coordinators (Phase 3: split coordinator)
    private lazy var copyVerifyExecutor: CopyVerifyExecutor = {
        CopyVerifyExecutor(
            platformManager: platformManager,
            timingService: timingService,
            errorService: errorService,
            stateService: stateService,
            backgroundTaskService: backgroundTaskService
        )
    }()
    private(set) lazy var comparisonCoordinator: ComparisonCoordinator = {
        ComparisonCoordinator(platformManager: platformManager)
    }()
    private(set) lazy var reportCoordinator: ReportCoordinator = {
        ReportCoordinator(platformManager: platformManager)
    }()
    
    // MARK: - File Selection State
    @Published var sourceURL: URL?
    @Published var destinationURLs: [URL] = []
    @Published var leftURL: URL? // For folder comparison
    @Published var rightURL: URL? // For folder comparison
    
    // MARK: - Camera Detection State
    @Published var detectedCamera: CameraCard?
    @Published var cameraDetectionInProgress = false
    
    // MARK: - Folder Info State (delegated to FolderInfoService)
    @Published var folderInfoService = FolderInfoService.shared
    @Published var lastCompareStats: CompareStats?

    // Convenience accessors for folder info (delegated to service)
    var sourceFolderInfo: EnhancedFolderInfo? { folderInfoService.sourceFolderInfo }
    var leftFolderInfo: EnhancedFolderInfo? { folderInfoService.leftFolderInfo }
    var rightFolderInfo: EnhancedFolderInfo? { folderInfoService.rightFolderInfo }
    var destinationFolderInfos: [URL: EnhancedFolderInfo] { folderInfoService.destinationFolderInfos }
    var folderInfoLoadingState: [URL: Bool] { folderInfoService.folderInfoLoadingState }
    
    private var cancellables = Set<AnyCancellable>()
    private var activeStartID: UUID?
    private var startCancellationRequested = false
    private var activeProjectCardID: UUID?

    // MARK: - iOS Background Task Service
    private let backgroundTaskService = IOSBackgroundTaskService.shared

    // Convenience accessors for iOS background state
    var backgroundTimeRemainingSeconds: Double? { backgroundTaskService.backgroundTimeRemainingSeconds }
    var isInBackground: Bool { backgroundTaskService.isInBackground }

    // MARK: - Initialization
    
    init(platformManager: PlatformManager) {
        self.platformManager = platformManager
        let projectStore = UserDefaultsPhotographerJobStore()
        self.photographerJobViewModel = PhotographerJobViewModel(
            store: projectStore,
            remoteBackupCoordinator: UnavailableRemoteProjectCoordinator(store: projectStore)
        )
        setupBindings()
        // Default first launch to checksum verification; honor last-picked thereafter.
        if let saved = UserDefaults.standard.string(forKey: "lastVerificationMode"),
           let mode = VerificationMode.allCases.first(where: { $0.rawValue == saved }) {
            verificationMode = mode
        } else {
            verificationMode = .standard
        }
    }
    
    #if os(iOS)
    convenience init() {
        self.init(platformManager: IOSPlatformManager.shared)
    }
    #endif
    
    #if os(macOS)
    convenience init() {
        self.init(platformManager: MacOSPlatformManager.shared)
    }
    #endif
    
    private func setupBindings() {
        // Monitor source URL changes for camera detection and folder info
        $sourceURL
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    if let url = url {
                        await self?.detectCameraFromSource(url)
                    }
                    self?.photographerJobViewModel.sourceDidChange(to: url)
                    await self?.folderInfoService.updateSource(url)
                }
            }
            .store(in: &cancellables)

        // Monitor left folder URL changes
        $leftURL
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateLeft(url)
                }
            }
            .store(in: &cancellables)

        // Monitor right folder URL changes
        $rightURL
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateRight(url)
                }
            }
            .store(in: &cancellables)

        // Monitor destination URLs changes
        $destinationURLs
            .sink { [weak self] urls in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateDestinations(urls)
                }
            }
            .store(in: &cancellables)

        // Forward folder info service changes to trigger UI updates
        folderInfoService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Persist verification mode across launches
        $verificationMode
            .sink { mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "lastVerificationMode")
            }
            .store(in: &cancellables)
    }

    // MARK: - UI Helpers
    
    func showAlert(title: String, message: String) async {
        await platformManager.presentAlert(title: title, message: message)
    }
    
    func showError(_ error: Error) async {
        await platformManager.presentError(error)
    }
    
    // MARK: - File Selection Methods
    
    func selectSourceFolder() async {
        sourceURL = await platformManager.fileSystem.selectSourceFolder()
    }
    
    func addDestinationFolder() async {
        let urls = await platformManager.fileSystem.selectDestinationFolders()
        for url in urls {
            if !destinationURLs.contains(url) {
                destinationURLs.append(url)
            }
        }
    }
    
    func removeDestinationFolder(_ url: URL) {
        destinationURLs.removeAll { $0 == url }
    }
    
    func selectLeftFolder() async {
        leftURL = await platformManager.fileSystem.selectLeftFolder()
    }
    
    func selectRightFolder() async {
        rightURL = await platformManager.fileSystem.selectRightFolder()
    }
    
    // MARK: - Operation Control

    func startOperation() async {
        guard activeStartID == nil, !isOperationInProgress else { return }
        guard let sourceURL = sourceURL, !destinationURLs.isEmpty else {
            operationState = .failed
            await platformManager.presentAlert(
                title: "Invalid Selection",
                message: "Please select a source folder and at least one destination folder."
            )
            return
        }

        let startID = UUID()
        activeStartID = startID
        startCancellationRequested = false
        isOperationInProgress = true
        defer {
            if activeStartID == startID {
                activeStartID = nil
                startCancellationRequested = false
                isOperationInProgress = false
            }
        }

        // iOS: Acquire security-scoped access BEFORE any FileManager operations
        // This is required for document picker URLs to work with FileManager on iOS
        // On macOS, these methods return true/no-op, so this is safe cross-platform
        let didStartSourceScope = platformManager.fileSystem.startAccessing(url: sourceURL)
        var destinationScopes: [URL: Bool] = [:]
        for destinationURL in destinationURLs {
            destinationScopes[destinationURL] = platformManager.fileSystem.startAccessing(url: destinationURL)
        }
        defer {
            if didStartSourceScope { platformManager.fileSystem.stopAccessing(url: sourceURL) }
            for (url, didStart) in destinationScopes where didStart {
                platformManager.fileSystem.stopAccessing(url: url)
            }
        }

        // Validate resolved destination paths before starting. Source-tree and
        // capacity checks run in the file operation after its manifest is built.
        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: sourceURL,
                destinations: destinationURLs,
                settings: cameraLabelSettings
            )
        } catch {
            operationState = .failed
            await platformManager.presentError(error)
            return
        }

        guard activeStartID == startID, !startCancellationRequested else { return }

        operationState = .inProgress
        results = []
        progress = nil

        let config = CopyVerifyConfig(
            operationId: startID,
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            verificationMode: verificationMode,
            cameraLabelSettings: cameraLabelSettings,
            reportSettings: reportSettings,
            estimatedFiles: sourceFolderInfo?.fileCount ?? 100,
            estimatedBytes: sourceFolderInfo?.totalSize ?? 1_000_000_000,
            currentMode: currentMode,
            photographerReportFinalizer: photographerReportFinalizer
        )

        let callbacks = CopyVerifyCallbacks(
            onProgress: { [weak self] progressUpdate in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else { return }
                self.progress = progressUpdate
                if self.activeProjectCardID != nil {
                    self.photographerJobViewModel.updateProgressStage(progressUpdate.currentStage)
                }
            },
            onResult: { [weak self] result in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else { return }
                if let idx = self.results.firstIndex(where: { $0.path == result.path && $0.destination == result.destination }) {
                    self.results[idx] = result
                } else {
                    self.results.append(result)
                }
            },
            onStateChange: { [weak self] state in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else { return }
                self.operationState = state
                self.updateProjectLifecycle(for: state)
            },
            onAuthoritativeResults: { [weak self] allResults in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else {
                    throw CancellationError()
                }
                self.results = allResults
            }
        )

        do {
            currentOperation = try await copyVerifyExecutor.execute(config: config, callbacks: callbacks)
        } catch {
            // Error already handled by executor
        }
    }

    /// Starts a prepared project ingest only after the ordinary transfer
    /// preflight is safe. The project finalizer remains attached through
    /// verification, so mobile completion retains its local evidence.
    @discardableResult
    func startProjectOperation() async -> Bool {
        guard operationReadinessAssessment.isReady,
              photographerJobViewModel.hasPreparedIngestAwaitingStart,
              let jobID = photographerJobViewModel.activeJob?.id,
              let cardID = photographerJobViewModel.activeCard?.id,
              photographerJobViewModel.preliminaryAnalysis != nil else {
            return false
        }
        guard photographerJobViewModel.beginIngest(
            destinationCount: destinationURLs.count,
            sourceURL: sourceURL,
            verificationMode: verificationMode
        ) else {
            return false
        }

        photographerReportFinalizer = { [weak photographerJobViewModel, jobID, cardID] results in
            guard let photographerJobViewModel,
                  photographerJobViewModel.activeJob?.id == jobID,
                  photographerJobViewModel.activeCard?.id == cardID,
                  let state = photographerJobViewModel.activeCard?.localState,
                  state == .copying || state == .verifying else {
                throw PhotographerReportError.cardNotReady
            }
            return try photographerJobViewModel.completeIngest(results: results)
        }
        activeProjectCardID = cardID
        await startOperation()
        return true
    }

    func cancelOperation() {
        if activeStartID != nil {
            startCancellationRequested = true
        }
        copyVerifyExecutor.cancel()
        if currentMode == .compareFolders {
            comparisonCoordinator.requestCancellation()
        }

        // Report cancellation to error service
        let context = ErrorContext.general(operation: "File Operation", stage: "Cancelled")
        errorService.reportWarning("Operation cancelled by user", context: context)
        errorService.completeErrorTracking()
        stateService.cancelOperation()
        NotificationCenter.default.post(name: .operationCancelledByUser, object: nil)
        
        operationState = .cancelled
        updateProjectLifecycle(for: .cancelled)
    }
    
    func pauseOperation() async {
        guard stateService.currentState.canPause else { return }
        
        // Pause the underlying file operations
        await platformManager.fileOperations.pauseOperation()
        
        // Update state service with current progress
        stateService.pauseOperation(reason: .userRequested, currentProgress: progress)
        
        // Update our operation state to match
        operationState = stateService.currentState
        
        // Update capabilities
        stateService.updateCapabilities(canPause: false, canResume: true)
        SharedLogger.info("Operation paused by user", category: .transfer)
    }
    
    func resumeOperation() async {
        guard stateService.currentState.canResume else { return }
        
        // Check if resume is recommended
        if let recommendation = stateService.getResumeRecommendation(),
           !recommendation.shouldResume {
            await platformManager.presentAlert(
                title: "Resume Not Recommended",
                message: recommendation.reason
            )
            return
        }
        
        // Resume the underlying file operations
        await platformManager.fileOperations.resumeOperation()
        
        // Update state service
        if stateService.resumeOperation() {
            operationState = stateService.currentState
            
            // Update capabilities
            stateService.updateCapabilities(canPause: true, canResume: false)
            SharedLogger.info("Operation resumed", category: .transfer)
        }
    }
    
    private func updateProjectLifecycle(for state: OperationState) {
        guard activeProjectCardID != nil else { return }
        switch state {
        case .verifying:
            photographerJobViewModel.updateProgressStage(.verifying)
        case .completed(let info):
            if !info.success { photographerJobViewModel.operationFailed() }
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        case .failed:
            photographerJobViewModel.operationFailed()
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        case .cancelled:
            photographerJobViewModel.cancelIngest()
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        default:
            break
        }
    }

    // MARK: - Camera Detection
    
    private func detectCameraFromSource(_ url: URL) async {
        cameraDetectionInProgress = true
        detectedCamera = nil
        
        let result = await platformManager.cameraDetection.detectCamera(from: url)
        
        detectedCamera = result.cameraCard
        cameraDetectionInProgress = false
        
        // Update camera label settings if we detected a camera
        if let camera = result.cameraCard, result.confidence > 0.8 {
            if cameraLabelSettings.label.isEmpty {
                cameraLabelSettings.label = camera.name
            }
        }
    }
    
    // MARK: - Folder Comparison (delegated to ComparisonCoordinator)

    func compareFolders() async {
        guard currentMode == .compareFolders else { return }
        guard let left = leftURL, let right = rightURL else {
            await platformManager.presentAlert(
                title: "Invalid Selection",
                message: "Please select both folders to compare."
            )
            return
        }

        isOperationInProgress = true
        operationState = .inProgress
        results = []
        lastCompareStats = nil
        errorService.clearCurrentErrors()
        progress = OperationProgress(
            overallProgress: 0.0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: 0,
            currentStage: .preparing,
            speed: nil,
            timeRemaining: nil
        )

        do {
            let stats = try await comparisonCoordinator.compareFolders(
                left: left,
                right: right,
                verificationMode: verificationMode,
                onProgress: { [weak self] prog in
                    self?.progress = prog
                }
            )
            self.lastCompareStats = stats
            isOperationInProgress = false
            let message: String
            if stats.isClean {
                message = "Folders match"
            } else {
                var issues: [String] = []
                if stats.mismatchedCount > 0 { issues.append("\(stats.mismatchedCount) mismatched") }
                if stats.onlyInLeftCount > 0 { issues.append("\(stats.onlyInLeftCount) only in source") }
                if stats.onlyInRightCount > 0 { issues.append("\(stats.onlyInRightCount) only in destination") }
                message = "Comparison found differences: \(issues.joined(separator: ", "))"
            }
            operationState = .completed(OperationCompletionInfo(success: stats.isClean, message: message))
            return
        } catch is CancellationError {
            isOperationInProgress = false
            operationState = .cancelled
            return
        } catch {
            isOperationInProgress = false
            operationState = .failed
            await platformManager.presentError(error)
            return
        }
    }
    
    // MARK: - Report Generation (delegated to ReportCoordinator)

    func generateReport() async {
        guard currentOperation != nil else {
            await platformManager.presentAlert(
                title: "No Operation Data",
                message: "Please complete a file operation before generating a report."
            )
            return
        }

        do {
            try await reportCoordinator.generateReport(
                sourceURL: sourceURL,
                sourceFolderInfo: sourceFolderInfo,
                destinationURLs: destinationURLs,
                destinationFolderInfos: destinationFolderInfos,
                detectedCamera: detectedCamera,
                timingService: timingService,
                verificationMode: verificationMode,
                cameraLabelSettings: cameraLabelSettings,
                operationState: operationState
            )
        } catch {
            await platformManager.presentError(error)
        }
    }
    
    // MARK: - Mode Management

    func switchMode(to mode: AppMode) {
        guard !isOperationInProgress else { return }
        currentMode = mode
    }

    func resetForNewOperation() {
        results = []
        progress = nil
        operationState = .notStarted
        currentOperation = nil
    }

    func togglePause() async {
        if canPause {
            await pauseOperation()
        } else if canResume {
            await resumeOperation()
        }
    }

    func saveVerificationMode() {
        UserDefaults.standard.set(verificationMode.rawValue, forKey: "lastVerificationMode")
    }

    // MARK: - Completion State (derived from OperationState)

    var completionState: CompletionState {
        switch operationState {
        case .completed(let info):
            if info.success {
                return .success(message: info.message)
            } else {
                return .issues(message: info.message)
            }
        case .failed:
            return .failed(message: "Operation failed")
        case .inProgress, .copying, .verifying, .resuming:
            return .inProgress
        case .idle, .notStarted, .paused, .cancelled:
            return .idle
        }
    }

    // MARK: - Computed Properties

    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify:
            return operationReadinessAssessment.isReady && !isOperationInProgress
        case .compareFolders:
            return leftURL != nil && rightURL != nil && !isOperationInProgress
        case .masterReport:
            return currentOperation != nil && !isOperationInProgress
        }
    }
    
    var progressPercentage: Double {
        return progress?.overallProgress ?? 0.0
    }
    
    var formattedSpeed: String? {
        return progress?.formattedSpeed
    }
    
    var formattedTimeRemaining: String? {
        return progress?.formattedTimeRemaining
    }
    
    var currentStage: ProgressStage {
        return progress?.currentStage ?? .idle
    }
    
    // MARK: - Timing Computed Properties
    
    var operationDuration: String? {
        return timingService.currentTiming?.formattedDuration
    }
    
    var averageOperationSpeed: String? {
        return timingService.currentTiming?.formattedSpeed
    }
    
    var operationHistory: [OperationTiming] {
        return timingService.timingHistory
    }
    
    var operationStats: OperationHistoryStats? {
        return timingService.getHistoryStats()
    }
    
    // MARK: - Error Computed Properties
    
    var currentErrors: [ErrorReport] {
        return errorService.currentErrors
    }
    
    var errorSummary: ErrorSummary? {
        return errorService.errorSummary
    }
    
    var hasErrors: Bool {
        return !errorService.currentErrors.isEmpty
    }
    
    var hasCriticalErrors: Bool {
        return errorService.getCriticalErrors().count > 0
    }
    
    var errorCount: Int {
        return errorService.currentErrors.filter { $0.category != .warning }.count
    }
    
    var warningCount: Int {
        return errorService.currentErrors.filter { $0.category == .warning }.count
    }
    
    // MARK: - Pause/Resume Computed Properties
    
    var canPause: Bool {
        return stateService.currentState.canPause
    }
    
    var canResume: Bool {
        return stateService.currentState.canResume
    }
    
    var isPaused: Bool {
        return stateService.currentState.isPaused
    }
    
    var pauseResumeCapabilities: PauseResumeCapabilities {
        return stateService.pauseResumeCapabilities
    }
    
    var savedOperations: [SavedOperationState] {
        return stateService.savedOperations
    }
    
    // MARK: - Folder Info Computed Properties

    func getFolderInfo(for url: URL) -> EnhancedFolderInfo? {
        return folderInfoService.getFolderInfo(for: url)
    }

    func isFolderInfoLoading(for url: URL) -> Bool {
        return folderInfoService.isFolderInfoLoading(for: url)
    }
    
    var sourceFolderSummary: String {
        guard let info = sourceFolderInfo else { return "No folder selected" }
        return "\(info.formattedFileCount) files • \(info.formattedSize)"
    }
    
    var destinationsSummary: String {
        guard !destinationURLs.isEmpty else { return "No destinations selected" }
        let totalCapacity = destinationFolderInfos.values.compactMap { 
            getDriveCapacity(for: $0.url) 
        }.reduce(0, +)
        
        if totalCapacity > 0 {
            let formattedCapacity = ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
            return "\(destinationURLs.count) destination\(destinationURLs.count == 1 ? "" : "s") • ~\(formattedCapacity) available"
        } else {
            return "\(destinationURLs.count) destination\(destinationURLs.count == 1 ? "" : "s")"
        }
    }
    
    private func getDriveCapacity(for url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let cap = values.volumeAvailableCapacity {
                return Int64(cap)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // Get folder info with type hints for professional display
    func getFolderDisplayInfo(for url: URL) -> FolderDisplayInfo? {
        guard let enhancedInfo = getFolderInfo(for: url) else { return nil }
        
        // Convert to base FolderInfo for compatibility
        let baseInfo = FolderInfo(
            url: enhancedInfo.url,
            fileCount: enhancedInfo.fileCount,
            totalSize: enhancedInfo.totalSize,
            lastModified: enhancedInfo.lastModified,
            isInternalDrive: enhancedInfo.isInternalDrive
        )
        
        let driveType = getDriveType(for: url)
        let availableSpace = getDriveCapacity(for: url)
        let isLoading = isFolderInfoLoading(for: url)
        
        return FolderDisplayInfo(
            baseInfo: baseInfo,
            driveType: driveType,
            availableSpace: availableSpace,
            isLoading: isLoading
        )
    }
    
    private func getDriveType(for url: URL) -> DriveType {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsInternalKey,
                .volumeNameKey
            ])
            
            if values.volumeIsRemovable == true || values.volumeIsEjectable == true {
                // Check if it's likely a camera card based on volume name
                if let name = values.volumeName?.lowercased() {
                    if name.contains("untitled") || name.hasPrefix("no name") || 
                       name.contains("cf") || name.contains("sd") {
                        return .cameraCard
                    }
                }
                return .externalDrive
            } else if values.volumeIsInternal == false {
                return .networkDrive
            } else {
                return .internalDrive
            }
        } catch {
            return .unknown
        }
    }
    
    // MARK: - Enhanced Folder Info Helpers
    
    /// Get a detailed summary for source folder including file types
    var sourceDetailedSummary: String? {
        guard let info = sourceFolderInfo else { return nil }
        var parts = [info.formattedFileCount + " files", info.formattedSize]
        
        if let topType = info.topFileTypes.first {
            parts.append("\(topType.count) \(topType.type) files")
        }
        
        return parts.joined(separator: " • ")
    }
    
    /// Get file type breakdown for source folder
    var sourceFileTypesBreakdown: [(type: String, count: Int)] {
        return sourceFolderInfo?.topFileTypes ?? []
    }
    
    /// Get operation readiness assessment
    var operationReadinessAssessment: OperationReadinessAssessment {
        guard let sourceURL else {
            return OperationReadinessAssessment(
                isReady: false,
                issues: ["No source folder selected"],
                warnings: [],
                estimatedDuration: nil
            )
        }
        
        var issues: [String] = []
        var warnings: [String] = []
        
        // Check destinations
        if destinationURLs.isEmpty {
            issues.append("No destination folders selected")
        }

        let uniqueDestinationPaths = Set(destinationURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        if uniqueDestinationPaths.count != destinationURLs.count {
            issues.append("Destination folders must be unique")
        }

        for destinationURL in destinationURLs {
            if SafetyValidator.isProtectedSystemPath(destinationURL) {
                issues.append("\(destinationURL.lastPathComponent): System folders cannot be used as destinations")
            } else if let issue = SafetyValidator.destinationSafetyIssue(source: sourceURL, destination: destinationURL) {
                issues.append("\(destinationURL.lastPathComponent): \(issue)")
            }
        }

        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: sourceURL,
                destinations: destinationURLs,
                settings: cameraLabelSettings
            )
        } catch {
            issues.append(error.localizedDescription)
        }

        if verificationMode == .quick {
            warnings.append("Quick mode only checks file size. Standard SHA-256 is safer for production transfers.")
        }
        
        // Check available space
        if let sourceInfo = sourceFolderInfo {
            for destinationURL in destinationURLs {
                if let _ = destinationFolderInfos[destinationURL],
                   let available = getDriveCapacity(for: destinationURL),
                   available > 0 {
                    let ratio = Double(sourceInfo.totalSize) / Double(available)
                    if ratio > 0.9 {
                        issues.append("Insufficient space on \(destinationURL.lastPathComponent)")
                    } else if ratio > 0.7 {
                        warnings.append("Limited space on \(destinationURL.lastPathComponent)")
                    }
                }
            }
        }
        
        // Estimate duration
        let estimatedMinutes = sourceFolderInfo.map { verificationMode.estimatedTime(fileCount: $0.fileCount) }
        
        return OperationReadinessAssessment(
            isReady: issues.isEmpty,
            issues: issues,
            warnings: warnings,
            estimatedDuration: estimatedMinutes
        )
    }
    
    /// Get source folder metadata summary for professional display
    var sourceFolderMetadata: FolderMetadataSummary? {
        guard let info = sourceFolderInfo else { return nil }
        
        return FolderMetadataSummary(
            fileCount: info.fileCount,
            totalSize: info.totalSize,
            averageFileSize: info.averageFileSize,
            largestFile: info.largestFile,
            fileTypeBreakdown: info.topFileTypes,
            dateRange: info.dateRangeDescription,
            driveType: getDriveType(for: info.url),
            lastModified: info.lastModified
        )
    }
}

struct CompareStats: Equatable {
    let onlyInLeftCount: Int
    let onlyInRightCount: Int
    let commonCount: Int
    let mismatchedCount: Int

    /// True only when both folders contain the same files with matching content.
    var isClean: Bool {
        onlyInLeftCount == 0 && onlyInRightCount == 0 && mismatchedCount == 0
    }
}

// MARK: - Supporting Types for Enhanced Folder Display

struct OperationReadinessAssessment {
    let isReady: Bool
    let issues: [String]
    let warnings: [String]
    let estimatedDuration: String?
    
    var hasIssues: Bool { !issues.isEmpty }
    var hasWarnings: Bool { !warnings.isEmpty }
    
    var statusIcon: String {
        if !isReady { return "exclamationmark.triangle.fill" }
        if hasWarnings { return "exclamationmark.triangle" }
        return "checkmark.circle.fill"
    }
    
    var statusColor: Color {
        if !isReady { return .red }
        if hasWarnings { return .orange }
        return .green
    }
    
    var statusMessage: String {
        if !isReady {
            return "Cannot start: \(issues.joined(separator: ", "))"
        }
        if hasWarnings {
            return "Ready with warnings: \(warnings.joined(separator: ", "))"
        }
        return "Ready to start"
    }
}

struct FolderMetadataSummary {
    let fileCount: Int
    let totalSize: Int64
    let averageFileSize: Int64
    let largestFile: (name: String, size: Int64)?
    let fileTypeBreakdown: [(type: String, count: Int)]
    let dateRange: String
    let driveType: DriveType
    let lastModified: Date
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedAverageSize: String {
        ByteCountFormatter.string(fromByteCount: averageFileSize, countStyle: .file)
    }
    
    var formattedLargestFile: String? {
        guard let largest = largestFile else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: largest.size, countStyle: .file)
        return "\(largest.name) (\(size))"
    }
    
    var primaryFileType: String? {
        return fileTypeBreakdown.first?.type
    }
    
    var diversityScore: String {
        let typeCount = fileTypeBreakdown.count
        if typeCount <= 1 { return "Uniform" }
        if typeCount <= 3 { return "Mixed" }
        return "Diverse"
    }
}

#if os(macOS)
import AppKit

#endif
