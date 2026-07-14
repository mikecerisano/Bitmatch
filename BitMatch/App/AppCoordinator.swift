// AppCoordinator.swift - Thin macOS adapter around SharedAppCoordinator
// Phase 3: Slimmed from 588 lines to ~180 lines
// Retains macOS-specific ViewModels for backward UI compatibility
import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Shared Core (single source of truth)
    let sharedCoordinator = SharedAppCoordinator(platformManager: MacOSPlatformManager.shared)
    private var cancellables = Set<AnyCancellable>()
    private var lastSharedBytesProcessed: Int64 = 0

    // MARK: - macOS-Specific ViewModels (backward compat for views)
    @Published var progressViewModel = ProgressViewModel()
    @Published var fileSelectionViewModel = FileSelectionViewModel()
    @Published var cameraLabelViewModel = CameraLabelViewModel()
    @Published var settingsViewModel = SettingsViewModel()
    @Published var cameraDetectionService = CameraCardDetectionService()
    @Published var photographerJobViewModel: PhotographerJobViewModel

    // MARK: - Delegated State
    @Published var currentMode: AppMode = .copyAndVerify
    @Published var timeEstimate: TimeEstimate?
    @Published var isCalculatingEstimate = false

    // MARK: - Computed Properties (delegated to SharedAppCoordinator)
    var isOperationInProgress: Bool { sharedCoordinator.isOperationInProgress }
    var completionState: CompletionState { sharedCoordinator.completionState }
    var results: [ResultRow] { sharedCoordinator.results }
    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify: return fileSelectionViewModel.canCopyAndVerify
        case .compareFolders: return fileSelectionViewModel.canCompare
        case .masterReport: return false
        }
    }
    var progressPercentage: Double { progressViewModel.displayProgress }
    var currentFileName: String? { progressViewModel.currentFileName }
    var formattedSpeed: String? { progressViewModel.formattedSpeed }
    var formattedTimeRemaining: String? { progressViewModel.formattedTimeRemaining }
    var canPause: Bool { sharedCoordinator.canPause }
    var canResume: Bool { sharedCoordinator.canResume }
    var isPaused: Bool { sharedCoordinator.isPaused }
    var operationState: OperationState { sharedCoordinator.operationState }
    var verificationMode: VerificationMode {
        get { sharedCoordinator.verificationMode }
        set { sharedCoordinator.verificationMode = newValue }
    }

    // MARK: - Actions (delegated)
    func startOperation() {
        // Sync macOS VM state into SharedAppCoordinator
        sharedCoordinator.currentMode = currentMode
        var operationSettings = cameraLabelViewModel.destinationLabelSettings
        if photographerJobViewModel.activeCardDraft != nil,
           let renderedRecipe = photographerJobViewModel.renderedRecipe {
            operationSettings = PhotographerDestinationResolver.operationSettings(
                base: operationSettings,
                renderedRecipe: renderedRecipe
            )
        }
        sharedCoordinator.cameraLabelSettings = operationSettings
        sharedCoordinator.reportSettings = settingsViewModel.prefs
        sharedCoordinator.sourceURL = fileSelectionViewModel.sourceURL
        sharedCoordinator.destinationURLs = fileSelectionViewModel.destinationURLs
        sharedCoordinator.leftURL = fileSelectionViewModel.leftURL
        sharedCoordinator.rightURL = fileSelectionViewModel.rightURL

        progressViewModel.setProgressMessage("Preparing transfer…")
        progressViewModel.startProgressTracking()

        Task { @MainActor in
            switch currentMode {
            case .copyAndVerify:
                await sharedCoordinator.startOperation()
                if photographerJobViewModel.activeCard?.localState == .notStarted {
                    photographerJobViewModel.operationFailed()
                }
            case .compareFolders: await sharedCoordinator.compareFolders()
            case .masterReport: break
            }
        }
    }

    func cancelOperation() {
        sharedCoordinator.cancelOperation()
    }

    func togglePause() {
        Task { await sharedCoordinator.togglePause() }
    }

    func switchMode(to mode: AppMode) {
        guard !isOperationInProgress else { return }
        currentMode = mode
    }

    func resetForNewOperation() {
        sharedCoordinator.resetForNewOperation()
        progressViewModel.reset()
    }

    func saveVerificationMode() {
        sharedCoordinator.saveVerificationMode()
    }

    // MARK: - Camera Detection
    func toggleCameraDetection(_ enabled: Bool) {
        settingsViewModel.prefs.enableAutoCameraDetection = enabled
        if enabled { cameraDetectionService.startMonitoring() }
        else { cameraDetectionService.stopMonitoring() }
    }

    func rescanForCameras() {
        cameraDetectionService.rescanVolumes()
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

    // MARK: - Initialization
    init(photographerJobViewModel: PhotographerJobViewModel? = nil) {
        if let photographerJobViewModel {
            self.photographerJobViewModel = photographerJobViewModel
        } else {
            let store = CoreDataPhotographerJobStore(persistence: BitMatchPersistenceController.shared)
            self.photographerJobViewModel = PhotographerJobViewModel(store: store)
        }
        setupFileSelectionBindings()
        setupProgressBindings()
        setupSharedCoordinatorBindings()
        setupCameraDetection()
    }

    private func setupFileSelectionBindings() {
        // Camera detection with memory when source changes
        fileSelectionViewModel.$sourceURL.sink { [weak self] url in
            if let url = url { self?.cameraLabelViewModel.detectCameraWithMemory(at: url) }
            else { self?.cameraLabelViewModel.clearCameraLabel() }
            self?.updateTimeEstimate()
        }.store(in: &cancellables)

        fileSelectionViewModel.$destinationURLs
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateTimeEstimate() }
            .store(in: &cancellables)

        fileSelectionViewModel.$sourceFolderInfo
            .sink { [weak self] _ in self?.updateTimeEstimate() }
            .store(in: &cancellables)

        fileSelectionViewModel.$destinationURLs
            .sink { [weak self] dests in
                if !dests.isEmpty { self?.fileSelectionViewModel.saveLastDestinations() }
            }.store(in: &cancellables)

        cameraLabelViewModel.$destinationLabelSettings
            .sink { [weak self] _ in self?.cameraLabelViewModel.onLabelChanged() }
            .store(in: &cancellables)

        Publishers.MergeMany(
            fileSelectionViewModel.$sourceURL.map { _ in () }.eraseToAnyPublisher(),
            fileSelectionViewModel.$destinationURLs.map { _ in () }.eraseToAnyPublisher(),
            fileSelectionViewModel.$leftURL.map { _ in () }.eraseToAnyPublisher(),
            fileSelectionViewModel.$rightURL.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)
    }

    private func setupProgressBindings() {
        Publishers.MergeMany(
            progressViewModel.$fileCountTotal.map { _ in () }.eraseToAnyPublisher(),
            progressViewModel.$interpolatedProgress.map { _ in () }.eraseToAnyPublisher(),
            progressViewModel.$currentFileName.map { _ in () }.eraseToAnyPublisher(),
            progressViewModel.$bytesPerSecond.map { _ in () }.eraseToAnyPublisher(),
            progressViewModel.$filesPerSecond.map { _ in () }.eraseToAnyPublisher(),
            progressViewModel.$estimatedTimeRemaining.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)
    }

    // MARK: - Shared Core Bindings
    private func setupSharedCoordinatorBindings() {
        // Map SharedAppCoordinator progress → ProgressViewModel
        sharedCoordinator.$progress.compactMap { $0 }
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] prog in
                guard let self else { return }
                self.progressViewModel.setFileCountTotal(prog.totalFiles)
                self.progressViewModel.setPlannedTotalBytes(prog.totalBytes)
                self.progressViewModel.fileCountCompleted = prog.filesProcessed
                let destCount = self.fileSelectionViewModel.destinationURLs.count
                if let totals = prog.perDestinationTotals, let completed = prog.perDestinationCompleted,
                   totals.count == destCount, completed.count == destCount {
                    self.progressViewModel.setPerDestinationProgress(totals: totals, completed: completed)
                }
                if let name = prog.currentFile, !name.isEmpty { self.progressViewModel.setCurrentFile(name) }
                if let reused = prog.reusedCopies { self.progressViewModel.setReusedFileCopies(reused) }
                if let bytes = prog.bytesProcessed {
                    let delta = bytes - self.lastSharedBytesProcessed
                    if delta > 0 { self.progressViewModel.updateBytesProcessed(delta) }
                    self.lastSharedBytesProcessed = bytes
                }
                var msg = prog.currentStage.displayName
                if let name = prog.currentFile, !name.isEmpty { msg += " — \(name)" }
                self.progressViewModel.setProgressMessage(msg)
            }.store(in: &cancellables)

        // Lifecycle consumes every authoritative progress publication. The
        // throttled subscription above exists only to pace presentation work.
        sharedCoordinator.$progress.compactMap { $0 }
            .sink { [weak self] progress in
                guard let self, self.currentMode == .copyAndVerify else { return }
                self.photographerJobViewModel.updateProgressStage(progress.currentStage)
            }
            .store(in: &cancellables)

        // Map operation state for progress timer management
        sharedCoordinator.$operationState.sink { [weak self] state in
            guard let self else { return }
            switch state {
            case .inProgress, .copying, .verifying:
                self.progressViewModel.startProgressTracking()
                if self.progressViewModel.progressMessage == "Ready" {
                    self.progressViewModel.setProgressMessage("Preparing transfer…")
                }
                if self.currentMode == .copyAndVerify {
                    switch state {
                    case .inProgress, .copying:
                        self.photographerJobViewModel.beginIngest(
                            destinationCount: self.sharedCoordinator.destinationURLs.count
                        )
                    case .verifying:
                        self.photographerJobViewModel.updateProgressStage(.verifying)
                    default:
                        break
                    }
                }
            case .completed:
                self.progressViewModel.stopProgressTracking()
                self.lastSharedBytesProcessed = 0
            case .failed, .cancelled:
                self.progressViewModel.stopProgressTracking()
                self.lastSharedBytesProcessed = 0
                if self.currentMode == .copyAndVerify {
                    if state == .cancelled {
                        self.photographerJobViewModel.cancelIngest()
                    } else {
                        self.photographerJobViewModel.operationFailed()
                    }
                }
            default: break
            }
        }.store(in: &cancellables)

        // CopyVerifyExecutor publishes .completed before its onComplete callback
        // replaces presentation rows with the complete authoritative array.
        // Gating on completed here ensures incremental onResult rows are never
        // treated as terminal evidence.
        sharedCoordinator.$results.sink { [weak self] authoritativeResults in
            guard let self,
                  self.currentMode == .copyAndVerify,
                  case .completed = self.sharedCoordinator.operationState,
                  let state = self.photographerJobViewModel.activeCard?.localState,
                  state == .copying || state == .verifying else { return }
            try? self.photographerJobViewModel.completeIngest(results: authoritativeResults)
        }.store(in: &cancellables)

        photographerJobViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Publishers.MergeMany(
            sharedCoordinator.$isOperationInProgress.map { _ in () }.eraseToAnyPublisher(),
            sharedCoordinator.$operationState.map { _ in () }.eraseToAnyPublisher(),
            sharedCoordinator.$results.map { _ in () }.eraseToAnyPublisher(),
            sharedCoordinator.$verificationMode.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)
    }

    private func setupCameraDetection() {
        NotificationCenter.default.publisher(for: .cameraCardDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let cameraCard = notification.userInfo?["cameraCard"] as? CameraCard else { return }
                guard let self, self.settingsViewModel.prefs.enableAutoCameraDetection,
                      self.settingsViewModel.prefs.autoPopulateSource,
                      self.fileSelectionViewModel.sourceURL == nil else { return }
                self.fileSelectionViewModel.sourceURL = cameraCard.mediaPath
            }.store(in: &cancellables)

        if settingsViewModel.prefs.enableAutoCameraDetection {
            cameraDetectionService.startMonitoring()
        }
    }
}
