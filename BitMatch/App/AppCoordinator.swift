// Core/ViewModels/AppCoordinator.swift
import Foundation
import SwiftUI
import Combine
import UserNotifications

/// Main coordinator that manages all ViewModels and their interactions
@MainActor
final class AppCoordinator: ObservableObject {
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
        switch currentMode {
        case .copyAndVerify:
            guard fileSelectionViewModel.canCopyAndVerify else { return }
            operationViewModel.startCopyAndVerify()
        case .compareFolders:
            guard fileSelectionViewModel.canCompare else { return }
            operationViewModel.startComparison()
        case .masterReport:
            // Master Report doesn't have a "start" operation - it's scan-based
            break
        }
    }
    
    func cancelOperation() {
        operationViewModel.cancelOperation()
    }
    
    func togglePause() {
        operationViewModel.togglePause()
    }
    
    func switchMode(to mode: AppMode) {
        guard !isOperationInProgress else { return }
        currentMode = mode
    }
    
    func resetForNewOperation() {
        operationViewModel.resetCompletionState()
    }
    
    // MARK: - Smart Defaults Support
    
    func saveVerificationMode() {
        UserDefaults.standard.set(verificationMode.rawValue, forKey: "lastVerificationMode")
    }
    
    private func loadSavedPreferences() {
        // Load last verification mode
        if let savedMode = UserDefaults.standard.string(forKey: "lastVerificationMode"),
           let mode = VerificationMode.allCases.first(where: { $0.rawValue == savedMode }) {
            verificationMode = mode
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
            }
            .store(in: &cancellables)
        
        // Update verification mode when settings change
        settingsViewModel.prefs.$verifyWithChecksum
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
        
        // Save verification mode when it changes
        operationViewModel.$verificationMode
            .sink { [weak self] mode in
                self?.saveVerificationMode()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Initialization
    init() {
        loadSavedPreferences()
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
        
        // Initialize operationViewModel early to ensure proper binding
        _ = operationViewModel
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
        
        // Update camera info if available
        if let volumeInfo = VolumeScanner.getVolumeInfo(for: cameraCard.volumeURL) {
            let sourceFolderInfo = FolderInfo(
                name: cameraCard.mediaPath.lastPathComponent,
                fileCount: volumeInfo.estimatedFileCount ?? 0,
                totalSize: volumeInfo.totalSize ?? 0,
                isInternalDrive: !volumeInfo.isRemovable,
                icon: NSWorkspace.shared.icon(forFile: cameraCard.volumeURL.path),
                volumeName: volumeInfo.name,
                cameraType: cameraCard.cameraType.rawValue
            )
            fileSelectionViewModel.sourceFolderInfo = sourceFolderInfo
        }
        
        print("📷 Auto-populated source with \(cameraCard.cameraType.displayName): \(cameraCard.mediaPath.path)")
        
        // Show success notification
        showCameraDetectionAlert(cameraCard: cameraCard, autoPopulated: true)
    }
    
    private func showCameraDetectionAlert(cameraCard: CameraCard, autoPopulated: Bool) {
        // Show system notification if enabled
        if settingsViewModel.prefs.showCameraDetectionNotifications {
            let content = UNMutableNotificationContent()
            content.title = "Camera Card Detected"
            content.body = "\(cameraCard.cameraType.displayName) detected on \(cameraCard.volumeURL.lastPathComponent)"
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // Show immediately
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Failed to show notification: \(error)")
                }
            }
        }
        
        let alert = NSAlert()
        alert.messageText = "Camera Card Detected"
        
        if autoPopulated {
            alert.informativeText = "\(cameraCard.cameraType.displayName) detected and automatically set as source.\n\nLocation: \(cameraCard.volumeURL.lastPathComponent)"
            alert.addButton(withTitle: "Continue")
        } else {
            alert.informativeText = "\(cameraCard.cameraType.displayName) detected on \(cameraCard.volumeURL.lastPathComponent).\n\nWould you like to set it as the source?"
            alert.addButton(withTitle: "Set as Source")
            alert.addButton(withTitle: "Ignore")
        }
        
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        if !autoPopulated && response == .alertFirstButtonReturn {
            // User chose to set as source manually
            fileSelectionViewModel.sourceURL = cameraCard.mediaPath
            
            if let volumeInfo = VolumeScanner.getVolumeInfo(for: cameraCard.volumeURL) {
                let sourceFolderInfo = FolderInfo(
                    name: cameraCard.mediaPath.lastPathComponent,
                    fileCount: volumeInfo.estimatedFileCount ?? 0,
                    totalSize: volumeInfo.totalSize ?? 0,
                    isInternalDrive: !volumeInfo.isRemovable,
                    icon: NSWorkspace.shared.icon(forFile: cameraCard.volumeURL.path),
                    volumeName: volumeInfo.name,
                    cameraType: cameraCard.cameraType.rawValue
                )
                fileSelectionViewModel.sourceFolderInfo = sourceFolderInfo
            }
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
