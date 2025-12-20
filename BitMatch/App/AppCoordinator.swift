// Core/ViewModels/AppCoordinator.swift
import Foundation
import SwiftUI
import Combine
import UserNotifications
// Thin adapter: prepare bridging to SharedAppCoordinator for mac target

// NOTE: This adapter is initially disabled (useSharedCore = false)
// to avoid UI behavior changes. Flip the flag via enableSharedCore(true)
// or by setting UserDefaults key "UseSharedCoreAdapter" to true to test.

/// Main coordinator that manages all ViewModels and their interactions
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Shared Core Adapter
    @Published private(set) var useSharedCore: Bool = false
    private let sharedCoordinator = SharedAppCoordinator(platformManager: MacOSPlatformManager.shared)
    private var sharedCancellables = Set<AnyCancellable>()
    private var lastSharedBytesProcessed: Int64 = 0

    // MARK: - Child ViewModels
    @Published var progressViewModel = ProgressViewModel()
    @Published var fileSelectionViewModel = FileSelectionViewModel()
    @Published var cameraLabelViewModel = CameraLabelViewModel()
    @Published var settingsViewModel = SettingsViewModel()
    @Published var cameraDetectionService = CameraCardDetectionService()
    
    // For managing Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // Non-lazy initialization to ensure proper binding
    private var _operationViewModel: OperationViewModel?
    var operationViewModel: OperationViewModel {
        if _operationViewModel == nil {
            _operationViewModel = OperationViewModel(
                progressViewModel: progressViewModel,
                fileSelectionViewModel: fileSelectionViewModel,
                cameraLabelViewModel: cameraLabelViewModel,
                settingsViewModel: settingsViewModel
            )
            
            // Subscribe to operationViewModel changes to trigger UI updates
            let cancellable = _operationViewModel!.objectWillChange.sink { [weak self] _ in
                // Use async delay to avoid "modifying state during view update" warnings
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms delay
                    self?.objectWillChange.send()
                }
            }
            cancellables.insert(cancellable)
        }
        return _operationViewModel!
    }
    
    // MARK: - App State
    @Published var currentMode: AppMode = .copyAndVerify
    @Published var timeEstimate: TimeEstimate?
    @Published var isCalculatingEstimate = false
    
    // MARK: - Computed Properties
    var isOperationInProgress: Bool {
        operationViewModel.isVerifying
    }
    
    var completionState: CompletionState {
        operationViewModel.completionState
    }
    
    var results: [ResultRow] {
        operationViewModel.results
    }
    
    var verificationMode: VerificationMode {
        get { operationViewModel.verificationMode }
        set { operationViewModel.verificationMode = newValue }
    }
    
    // MARK: - Public Actions
    func startOperation() {
        if useSharedCore {
            // Bridge current selections/settings into SharedAppCoordinator
            sharedCoordinator.currentMode = currentMode
            sharedCoordinator.verificationMode = verificationMode
            sharedCoordinator.cameraLabelSettings = cameraLabelViewModel.destinationLabelSettings
            sharedCoordinator.reportSettings = settingsViewModel.prefs
            sharedCoordinator.sourceURL = fileSelectionViewModel.sourceURL
            sharedCoordinator.destinationURLs = fileSelectionViewModel.destinationURLs
            sharedCoordinator.leftURL = fileSelectionViewModel.leftURL
            sharedCoordinator.rightURL = fileSelectionViewModel.rightURL

            // Prime UI: show preparing message and start progress timer
            progressViewModel.setProgressMessage("Preparing transfer…")
            progressViewModel.startProgressTracking()

            Task { @MainActor in
                switch currentMode {
                case .copyAndVerify:
                    await sharedCoordinator.startOperation()
                case .compareFolders:
                    await sharedCoordinator.compareFolders()
                case .masterReport:
                    break
                }
            }
        } else {
            switch currentMode {
            case .copyAndVerify:
                guard fileSelectionViewModel.canCopyAndVerify else { return }
                cameraDetectionService.stopMonitoring()
                // Immediately indicate preparing state so users see activity
                progressViewModel.setProgressMessage("Preparing transfer…")
                progressViewModel.startProgressTracking()
                operationViewModel.startCopyAndVerify()
            case .compareFolders:
                guard fileSelectionViewModel.canCompare else { return }
                progressViewModel.setProgressMessage("Preparing comparison…")
                progressViewModel.startProgressTracking()
                operationViewModel.startComparison()
            case .masterReport:
                break
            }
        }
    }
    
    func cancelOperation() {
        if useSharedCore {
            sharedCoordinator.cancelOperation()
            NotificationCenter.default.post(name: .operationCancelledByUser, object: nil)
        } else {
            operationViewModel.cancelOperation()
            progressViewModel.stopProgressTracking()
            NotificationCenter.default.post(name: .operationCancelledByUser, object: nil)
        }
    }
    
    func togglePause() {
        if useSharedCore {
            Task { @MainActor in
                if sharedCoordinator.stateService.currentState.canPause {
                    await sharedCoordinator.pauseOperation()
                } else if sharedCoordinator.stateService.currentState.canResume {
                    await sharedCoordinator.resumeOperation()
                }
            }
        } else {
            operationViewModel.togglePause()
        }
    }
    
    func switchMode(to mode: AppMode) {
        guard !isOperationInProgress else { return }
        currentMode = mode
    }
    
    func resetForNewOperation() {
        if useSharedCore {
            // Reset legacy VM for UI cleanliness; shared coordinator resets itself between operations
            operationViewModel.resetCompletionState()
        } else {
            operationViewModel.resetCompletionState()
        }
    }
    
    // MARK: - Smart Defaults Support
    
    func saveVerificationMode() {
        UserDefaults.standard.set(verificationMode.rawValue, forKey: "lastVerificationMode")
    }
    
    private func loadSavedPreferences() {
        // Load last verification mode; default to .quick on first boot
        if let savedMode = UserDefaults.standard.string(forKey: "lastVerificationMode"),
           let mode = VerificationMode.allCases.first(where: { $0.rawValue == savedMode }) {
            verificationMode = mode
        } else {
            verificationMode = .quick
        }
    }
    
    // MARK: - Time Estimate

    func updateTimeEstimate() {
        guard let sourceURL = fileSelectionViewModel.sourceURL,
              !fileSelectionViewModel.destinationURLs.isEmpty,
              let totalBytes = fileSelectionViewModel.sourceFolderInfo?.totalSize,
              totalBytes > 0 else {
            timeEstimate = nil
            return
        }

        isCalculatingEstimate = true

        Task {
            let estimate = await DriveBenchmarkService.shared.estimateTransferTime(
                sourceURL: sourceURL,
                destinationURLs: fileSelectionViewModel.destinationURLs,
                totalBytes: totalBytes,
                verificationMode: verificationMode
            )

            await MainActor.run {
                self.timeEstimate = estimate
                self.isCalculatingEstimate = false
            }
        }
    }

    // MARK: - Setup & Observers
    func setupObservers() {
        // Camera detection with memory when source changes
        fileSelectionViewModel.$sourceURL
            .sink { [weak self] url in
                if let url = url {
                    // Use the memory-aware detection from CameraLabelViewModel
                    self?.cameraLabelViewModel.detectCameraWithMemory(at: url)
                } else {
                    // Clear camera label when no source is selected
                    self?.cameraLabelViewModel.clearCameraLabel()
                }
                // Update time estimate when source changes
                self?.updateTimeEstimate()
            }
            .store(in: &cancellables)

        // Update time estimate when destinations change
        fileSelectionViewModel.$destinationURLs
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTimeEstimate()
            }
            .store(in: &cancellables)

        // Update time estimate when source folder info is loaded
        fileSelectionViewModel.$sourceFolderInfo
            .sink { [weak self] _ in
                self?.updateTimeEstimate()
            }
            .store(in: &cancellables)
        
        // Update verification mode when settings change
        settingsViewModel.$prefs
            .map { $0.verifyWithChecksum }
            .sink { [weak self] useChecksum in
                // Update verification mode based on settings
                if useChecksum && self?.verificationMode == .standard {
                    self?.verificationMode = .thorough
                } else if !useChecksum && self?.verificationMode.useChecksum == true {
                    self?.verificationMode = .standard
                }
            }
            .store(in: &cancellables)
        
        // Save destinations when they change
        fileSelectionViewModel.$destinationURLs
            .sink { [weak self] destinations in
                if !destinations.isEmpty {
                    self?.fileSelectionViewModel.saveLastDestinations()
                }
            }
            .store(in: &cancellables)
        
        // Update camera memory when label changes
        cameraLabelViewModel.$destinationLabelSettings
            .sink { [weak self] _ in
                self?.cameraLabelViewModel.onLabelChanged()
            }
            .store(in: &cancellables)
        
        // Save verification mode when it changes and update time estimate
        operationViewModel.$verificationMode
            .sink { [weak self] mode in
                self?.saveVerificationMode()
                self?.updateTimeEstimate()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Initialization
    init() {
        loadSavedPreferences()
        // Load shared-core adapter flag
        if let stored = UserDefaults.standard.object(forKey: "UseSharedCoreAdapter") as? Bool {
            useSharedCore = stored
        } else {
            useSharedCore = true
        }
        setupObservers()
        setupCameraDetection()
        
        // Subscribe to fileSelectionViewModel changes to ensure UI updates
        let fileSelectionCancellable = fileSelectionViewModel.objectWillChange.sink { [weak self] _ in
            // Use async delay to avoid "modifying state during view update" warnings
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms delay
                self?.objectWillChange.send()
            }
        }
        cancellables.insert(fileSelectionCancellable)
        
        // Forward progress updates from nested ProgressViewModel
        let progressCancellable = progressViewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms delay
                self?.objectWillChange.send()
            }
        }
        cancellables.insert(progressCancellable)
        
        // Initialize operationViewModel early to ensure proper binding
        _ = operationViewModel
        
        // Prepare shared-core bindings (inactive until enabled)
        setupSharedCoreBindings()
    }
    
    // MARK: - Camera Detection Setup
    private func setupCameraDetection() {
        // Listen for camera card detection notifications
        NotificationCenter.default.publisher(for: .cameraCardDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCameraCardDetected(notification)
            }
            .store(in: &cancellables)
        
        // Start monitoring if auto-detection is enabled
        if settingsViewModel.prefs.enableAutoCameraDetection {
            cameraDetectionService.startMonitoring()
        }

        // Resume camera monitoring when operations finish
        operationViewModel.statePublisher
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .completed, .failed, .cancelled, .idle, .notStarted:
                    if self.settingsViewModel.prefs.enableAutoCameraDetection {
                        self.cameraDetectionService.startMonitoring()
                    }
                case .inProgress, .copying, .verifying, .paused, .resuming:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleCameraCardDetected(_ notification: Notification) {
        guard let cameraCard = notification.userInfo?["cameraCard"] as? CameraCard else {
            return
        }
        
        // Check if auto-population is enabled and no source is currently selected
        guard settingsViewModel.prefs.enableAutoCameraDetection,
              settingsViewModel.prefs.autoPopulateSource,
              fileSelectionViewModel.sourceURL == nil else {
            // Still show notification even if we don't auto-populate
            showCameraDetectionAlert(cameraCard: cameraCard, autoPopulated: false)
            return
        }
        
        // Auto-populate the source with detected camera
        fileSelectionViewModel.sourceURL = cameraCard.mediaPath
        
        // Update camera info
        let sourceFolderInfo = FolderInfo(
            url: cameraCard.mediaPath,
            fileCount: cameraCard.fileCount,
            totalSize: cameraCard.totalSize,
            lastModified: Date(),
            isInternalDrive: false
        )
        fileSelectionViewModel.sourceFolderInfo = sourceFolderInfo
        
        AppLogger.info("Auto-populated source with \(cameraCard.cameraType.description): \(cameraCard.mediaPath.path)", category: .transfer)
        
        // Show success notification
        showCameraDetectionAlert(cameraCard: cameraCard, autoPopulated: true)
    }
    
    private func showCameraDetectionAlert(cameraCard: CameraCard, autoPopulated: Bool) {
        // Show system notification if enabled
        if settingsViewModel.prefs.showCameraDetectionNotifications {
            let content = UNMutableNotificationContent()
            content.title = "Camera Card Detected"
            content.body = "\(cameraCard.cameraType.description) detected on \(cameraCard.volumeURL.lastPathComponent)"
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Show immediately
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    AppLogger.error("Failed to show notification: \(error)", category: .general)
                }
            }
        }
        
        let alert = NSAlert()
        alert.messageText = "Camera Card Detected"
        
        if autoPopulated {
            alert.informativeText = "\(cameraCard.cameraType.description) detected and automatically set as source.\n\nLocation: \(cameraCard.volumeURL.lastPathComponent)"
            alert.addButton(withTitle: "Continue")
        } else {
            alert.informativeText = "\(cameraCard.cameraType.description) detected on \(cameraCard.volumeURL.lastPathComponent).\n\nWould you like to set it as the source?"
            alert.addButton(withTitle: "Set as Source")
            alert.addButton(withTitle: "Ignore")
        }
        
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if !autoPopulated && response == .alertFirstButtonReturn {
            // User chose to set as source manually
            fileSelectionViewModel.sourceURL = cameraCard.mediaPath
            
            // Compute fresh volume info (file count/size) for accuracy
            var computedCount = 0
            var computedSize: Int64 = 0
            let fm = FileManager.default
            if let enumerator = fm.enumerator(at: cameraCard.mediaPath, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
                while let url = enumerator.nextObject() as? URL {
                    if let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), rv.isRegularFile == true {
                        computedCount += 1
                        computedSize += Int64(rv.fileSize ?? 0)
                    }
                }
            }
            let sourceFolderInfo = FolderInfo(
                url: cameraCard.mediaPath,
                fileCount: max(cameraCard.fileCount, computedCount),
                totalSize: max(cameraCard.totalSize, computedSize),
                lastModified: Date(),
                isInternalDrive: false
            )
            fileSelectionViewModel.sourceFolderInfo = sourceFolderInfo
        }
    }
    
    // MARK: - Camera Detection Controls
    func toggleCameraDetection(_ enabled: Bool) {
        settingsViewModel.prefs.enableAutoCameraDetection = enabled
        
        if enabled {
            cameraDetectionService.startMonitoring()
        } else {
            cameraDetectionService.stopMonitoring()
        }
    }
    
    func rescanForCameras() {
        cameraDetectionService.rescanVolumes()
    }
}

// MARK: - Shared Core Adapter Controls
extension AppCoordinator {
    func enableSharedCore(_ enabled: Bool) {
        useSharedCore = enabled
        UserDefaults.standard.set(enabled, forKey: "UseSharedCoreAdapter")
        AppLogger.info("Shared core adapter \(enabled ? "ENABLED" : "DISABLED")", category: .general)
    }
}

// MARK: - Shared Core Bindings
extension AppCoordinator {
    private func setupSharedCoreBindings() {
        // Progress mapping
        sharedCoordinator.$progress
            .compactMap { $0 }
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] prog in
                guard let self = self, self.useSharedCore else { return }
                // Set totals
                self.progressViewModel.setFileCountTotal(prog.totalFiles)
                self.progressViewModel.setPlannedTotalBytes(prog.totalBytes)
                // Completed files
                self.progressViewModel.fileCountCompleted = prog.filesProcessed
                // Reflect stage into OperationViewModel state for UI labels
                self.operationViewModel.applyStageFromShared(prog.currentStage)
                // Per-destination progress
                let destCount = self.fileSelectionViewModel.destinationURLs.count
                if let totals = prog.perDestinationTotals, let completed = prog.perDestinationCompleted,
                   totals.count == destCount, completed.count == destCount {
                    self.progressViewModel.setPerDestinationProgress(totals: totals, completed: completed)
                } else if destCount > 0, prog.totalFiles > 0,
                          self.progressViewModel.hasPerDestinationData(expectedCount: destCount) == false {
                    // Only mirror if we have no existing per-destination data yet
                    self.progressViewModel.mirrorPerDestinationProgress(
                        overallCompleted: prog.filesProcessed,
                        overallTotal: prog.totalFiles,
                        destinationCount: destCount
                    )
                }
                // Current file name
                if let name = prog.currentFile, !name.isEmpty {
                    self.progressViewModel.setCurrentFile(name)
                }
                // Reused copies
                if let reused = prog.reusedCopies { self.progressViewModel.setReusedFileCopies(reused) }
                // Bytes processed (delta)
                if let bytes = prog.bytesProcessed {
                    let delta = bytes - self.lastSharedBytesProcessed
                    if delta > 0 { self.progressViewModel.updateBytesProcessed(delta) }
                    self.lastSharedBytesProcessed = bytes
                }
                // Progress message
                var msg = prog.currentStage.displayName
                if let name = prog.currentFile, !name.isEmpty { msg += " — \(name)" }
                self.progressViewModel.setProgressMessage(msg)
            }
            .store(in: &sharedCancellables)

        // Results mapping (on change, replace mac results to keep UI in sync)
        sharedCoordinator.$results
            .sink { [weak self] rows in
                guard let self = self, self.useSharedCore else { return }
                self.operationViewModel.results = rows
            }
            .store(in: &sharedCancellables)

        // Operation state mapping for timers and completion
        sharedCoordinator.$operationState
            .sink { [weak self] state in
                guard let self = self, self.useSharedCore else { return }
                switch state {
                case .inProgress, .copying, .verifying:
                    self.progressViewModel.startProgressTracking()
                    if self.progressViewModel.progressMessage == "Ready" {
                        self.progressViewModel.setProgressMessage("Preparing transfer…")
                    }
                    self.operationViewModel.setActiveStateFromShared()
                case .completed(let info):
                    self.progressViewModel.stopProgressTracking()
                    self.progressViewModel.setProgressMessage(info.message)
                    self.lastSharedBytesProcessed = 0
                    self.operationViewModel.setCompletionFromShared(success: info.success, message: info.message)
                case .failed:
                    self.progressViewModel.stopProgressTracking()
                    self.lastSharedBytesProcessed = 0
                    self.operationViewModel.setFailedFromShared()
                case .cancelled:
                    self.progressViewModel.stopProgressTracking()
                    self.lastSharedBytesProcessed = 0
                    self.operationViewModel.setCancelledFromShared()
                    // Toast handled via existing .operationCancelledByUser notification in cancelOperation()
                default:
                    break
                }
            }
            .store(in: &sharedCancellables)
    }
}

// MARK: - Convenience Access
extension AppCoordinator {
    // Provide clean access to commonly needed properties
    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify:
            return fileSelectionViewModel.canCopyAndVerify
        case .compareFolders:
            return fileSelectionViewModel.canCompare
        case .masterReport:
            return false // Master Report uses scan button, not start operation
        }
    }
    
    var progressPercentage: Double {
        progressViewModel.displayProgress
    }
    
    var currentFileName: String? {
        progressViewModel.currentFileName
    }
    
    var formattedSpeed: String? {
        progressViewModel.formattedSpeed
    }
    
    var formattedTimeRemaining: String? {
        progressViewModel.formattedTimeRemaining
    }
}
