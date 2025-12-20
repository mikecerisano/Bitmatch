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
    
    // MARK: - Operation State
    @Published var isOperationInProgress = false
    @Published var operationState: OperationState = .notStarted
    @Published var progress: OperationProgress?
    @Published var results: [ResultRow] = []
    @Published var currentOperation: FileOperation?

    // Operation executor for copy/verify
    private lazy var copyVerifyExecutor: CopyVerifyExecutor = {
        CopyVerifyExecutor(
            platformManager: platformManager,
            timingService: timingService,
            errorService: errorService,
            stateService: stateService,
            backgroundTaskService: backgroundTaskService
        )
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
    private var compareCancellationRequested = false

    // Convenience accessors for folder info (delegated to service)
    var sourceFolderInfo: EnhancedFolderInfo? { folderInfoService.sourceFolderInfo }
    var leftFolderInfo: EnhancedFolderInfo? { folderInfoService.leftFolderInfo }
    var rightFolderInfo: EnhancedFolderInfo? { folderInfoService.rightFolderInfo }
    var destinationFolderInfos: [URL: EnhancedFolderInfo] { folderInfoService.destinationFolderInfos }
    var folderInfoLoadingState: [URL: Bool] { folderInfoService.folderInfoLoadingState }
    
    private var cancellables = Set<AnyCancellable>()

    // MARK: - iOS Background Task Service
    private let backgroundTaskService = IOSBackgroundTaskService.shared

    // Convenience accessors for iOS background state
    var backgroundTimeRemainingSeconds: Double? { backgroundTaskService.backgroundTimeRemainingSeconds }
    var isInBackground: Bool { backgroundTaskService.isInBackground }

    // MARK: - Initialization
    
    init(platformManager: PlatformManager) {
        self.platformManager = platformManager
        setupBindings()
        // Default verification mode to Quick on first launch; honor last-picked thereafter
        if let saved = UserDefaults.standard.string(forKey: "lastVerificationMode"),
           let mode = VerificationMode.allCases.first(where: { $0.rawValue == saved }) {
            verificationMode = mode
        } else {
            verificationMode = .quick
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
        guard !isOperationInProgress else { return }
        guard let sourceURL = sourceURL, !destinationURLs.isEmpty else {
            await platformManager.presentAlert(
                title: "Invalid Selection",
                message: "Please select a source folder and at least one destination folder."
            )
            return
        }

        isOperationInProgress = true
        operationState = .inProgress
        results = []
        progress = nil

        let config = CopyVerifyConfig(
            operationId: UUID(),
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            verificationMode: verificationMode,
            cameraLabelSettings: cameraLabelSettings,
            reportSettings: reportSettings,
            estimatedFiles: sourceFolderInfo?.fileCount ?? 100,
            estimatedBytes: sourceFolderInfo?.totalSize ?? 1_000_000_000,
            currentMode: currentMode
        )

        let callbacks = CopyVerifyCallbacks(
            onProgress: { [weak self] progressUpdate in
                self?.progress = progressUpdate
            },
            onResult: { [weak self] result in
                guard let self else { return }
                if let idx = self.results.firstIndex(where: { $0.path == result.path && $0.destination == result.destination }) {
                    self.results[idx] = result
                } else {
                    self.results.append(result)
                }
            },
            onStateChange: { [weak self] state in
                self?.operationState = state
            },
            onComplete: { [weak self] allResults in
                // Results already updated via onResult callback
                self?.isOperationInProgress = false
            }
        )

        do {
            currentOperation = try await copyVerifyExecutor.execute(config: config, callbacks: callbacks)
        } catch {
            // Error already handled by executor
        }

        isOperationInProgress = false
    }

    func cancelOperation() {
        copyVerifyExecutor.cancel()
        if currentMode == .compareFolders {
            compareCancellationRequested = true
        }

        // Report cancellation to error service
        let context = ErrorContext.general(operation: "File Operation", stage: "Cancelled")
        errorService.reportWarning("Operation cancelled by user", context: context)
        errorService.completeErrorTracking()
        stateService.cancelOperation()
        NotificationCenter.default.post(name: .operationCancelledByUser, object: nil)
        
        isOperationInProgress = false
        operationState = .cancelled
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
    
    // MARK: - Folder Comparison (for Compare mode)
    
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
        compareCancellationRequested = false
        progress = OperationProgress(
            overallProgress: 0.0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: 0,
            currentStage: .preparing,
            speed: nil,
            timeRemaining: nil
        )

        // Implement basic folder comparison using file system service
        do {
            let sourceFiles = try await platformManager.fileSystem.getFileList(from: left)
            let destFiles = try await platformManager.fileSystem.getFileList(from: right)

            let sourceMap = try buildFileMap(files: sourceFiles, base: left)
            let destMap = try buildFileMap(files: destFiles, base: right)

            let sourceSet = Set(sourceMap.keys)
            let destSet = Set(destMap.keys)

            let onlyInSource = sourceSet.subtracting(destSet)
            let onlyInDest = destSet.subtracting(sourceSet)
            let common = sourceSet.intersection(destSet)

            var mismatched: Set<String> = []
            let totalCommon = common.count
            var processedCommon = 0
            progress = OperationProgress(
                overallProgress: totalCommon == 0 ? 1.0 : 0.0,
                currentFile: nil,
                filesProcessed: 0,
                totalFiles: totalCommon,
                currentStage: .verifying,
                speed: nil,
                timeRemaining: nil
            )
            for key in common {
                if compareCancellationRequested { throw CancellationError() }
                try Task.checkCancellation()
                guard let src = sourceMap[key], let dst = destMap[key] else { continue }
                if src.size != dst.size {
                    mismatched.insert(key)
                } else if verificationMode == .quick {
                    // size-only comparison already done
                } else if verificationMode == .paranoid {
                    let matches = try await platformManager.checksum.performByteComparison(
                        sourceURL: src.url,
                        destinationURL: dst.url,
                        progressCallback: nil
                    )
                    if !matches { mismatched.insert(key) }
                } else if verificationMode.useChecksum {
                    var allMatch = true
                    let types = verificationMode == .thorough ? verificationMode.checksumTypes : [verificationMode.checksumTypes.first ?? .sha256]
                    for type in types {
                        let result = try await platformManager.checksum.verifyFileIntegrity(
                            sourceURL: src.url,
                            destinationURL: dst.url,
                            type: type,
                            progressCallback: nil
                        )
                        if !result.matches {
                            allMatch = false
                            break
                        }
                    }
                    if !allMatch { mismatched.insert(key) }
                }
                processedCommon += 1
                let overall = totalCommon == 0 ? 1.0 : Double(processedCommon) / Double(totalCommon)
                progress = OperationProgress(
                    overallProgress: overall,
                    currentFile: key,
                    filesProcessed: processedCommon,
                    totalFiles: totalCommon,
                    currentStage: .verifying,
                    speed: nil,
                    timeRemaining: nil
                )
            }

            let matched = common.subtracting(mismatched)
            
            // Publish stats for UI/tests
            self.lastCompareStats = CompareStats(
                onlyInLeftCount: onlyInSource.count,
                onlyInRightCount: onlyInDest.count,
                commonCount: matched.count,
                mismatchedCount: mismatched.count
            )
            SharedLogger.info("Comparison complete", category: .transfer)
            SharedLogger.debug("Only in source: \(onlyInSource.count)", category: .transfer)
            SharedLogger.debug("Only in destination: \(onlyInDest.count)", category: .transfer)
            SharedLogger.debug("Common files: \(matched.count)", category: .transfer)
            if !mismatched.isEmpty {
                SharedLogger.debug("Mismatched files: \(mismatched.count)", category: .transfer)
            }
        } catch is CancellationError {
            isOperationInProgress = false
            operationState = .cancelled
            return
        } catch {
            await platformManager.presentError(error)
        }
        
        isOperationInProgress = false
        operationState = .completed(OperationCompletionInfo(success: true, message: "Operation completed successfully"))
    }

    private func relativePath(from base: URL, to fileURL: URL) -> String {
        let basePath = base.path
        let fullPath = fileURL.path
        if fullPath.hasPrefix(basePath + "/") {
            return String(fullPath.dropFirst(basePath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func buildFileMap(files: [URL], base: URL) throws -> [String: (url: URL, size: Int64)] {
        var map: [String: (url: URL, size: Int64)] = [:]
        map.reserveCapacity(files.count)
        for fileURL in files {
            let key = relativePath(from: base, to: fileURL)
            let size = try platformManager.fileSystem.getFileSize(for: fileURL)
            map[key] = (fileURL, size)
        }
        return map
    }
    
    // MARK: - Report Generation
    
    func generateReport() async {
        guard currentOperation != nil else {
            await platformManager.presentAlert(
                title: "No Operation Data",
                message: "Please complete a file operation before generating a report."
            )
            return
        }

        do {
            // Build a minimal TransferCard from current state
            let srcInfo: FolderInfo = try {
                if let info = sourceFolderInfo {
                    return FolderInfo(url: info.url, fileCount: info.fileCount, totalSize: info.totalSize, lastModified: info.lastModified, isInternalDrive: false)
                } else if let src = sourceURL {
                    return FolderInfo(url: src, fileCount: 0, totalSize: 0, lastModified: Date(), isInternalDrive: false)
                } else {
                    throw NSError(domain: "BitMatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing source info for report"])
                }
            }()
            let destInfos: [FolderInfo] = destinationURLs.map { url in
                if let info = destinationFolderInfos[url] {
                    return FolderInfo(url: info.url, fileCount: info.fileCount, totalSize: info.totalSize, lastModified: info.lastModified, isInternalDrive: false)
                } else {
                    return FolderInfo(url: url, fileCount: 0, totalSize: 0, lastModified: Date(), isInternalDrive: false)
                }
            }

            let transfer = TransferCard(
                source: srcInfo,
                destinations: destInfos,
                cameraCard: detectedCamera,
                metadata: TransferMetadata(
                    sourceURL: srcInfo.url,
                    destinationURLs: destInfos.map { $0.url },
                    startTime: timingService.currentTiming?.startTime ?? Date(),
                    endTime: Date(),
                    totalFiles: sourceFolderInfo?.fileCount ?? 0,
                    totalSize: sourceFolderInfo?.totalSize ?? 0,
                    verificationMode: verificationMode,
                    cameraSettings: cameraLabelSettings
                ),
                progress: 1.0,
                state: .completed(OperationCompletionInfo(success: true, message: ""))
            )

            let config = SharedReportGenerationService.ReportConfiguration.default()
            let generator = SharedReportGenerationService()
            let result = try await generator.generateMasterReport(transfers: [transfer], configuration: config)

            // Persist to temp and open
            let tempDir = FileManager.default.temporaryDirectory
            let timestamp = Int(Date().timeIntervalSince1970)
            let pdfURL = tempDir.appendingPathComponent("BitMatch_Report_\(timestamp).pdf")
            let jsonURL = tempDir.appendingPathComponent("BitMatch_Report_\(timestamp).json")
            try result.pdfData.write(to: pdfURL)
            try result.jsonData.write(to: jsonURL)

            _ = await platformManager.openURL(pdfURL)
        } catch {
            await platformManager.presentError(error)
        }
    }
    
    // MARK: - Computed Properties
    
    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify:
            return sourceURL != nil && !destinationURLs.isEmpty && !isOperationInProgress
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
        guard let sourceInfo = sourceFolderInfo else {
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
        
        // Check available space
        for destinationURL in destinationURLs {
            if let _ = destinationFolderInfos[destinationURL],
               let available = getDriveCapacity(for: destinationURL) {
                let ratio = Double(sourceInfo.totalSize) / Double(available)
                if ratio > 0.9 {
                    issues.append("Insufficient space on \(destinationURL.lastPathComponent)")
                } else if ratio > 0.7 {
                    warnings.append("Limited space on \(destinationURL.lastPathComponent)")
                }
            }
        }
        
        // Estimate duration
        let estimatedMinutes = verificationMode.estimatedTime(fileCount: sourceInfo.fileCount)
        
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
