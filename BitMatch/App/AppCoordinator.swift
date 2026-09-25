// AppCoordinator.swift - macOS adapter around SharedAppCoordinator
// Mirrors shared state into macOS-only view models (progress, file selection,
// camera label, settings) through Combine subscriptions. iPad and iPhone use
// SharedAppCoordinator directly.
import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Shared Core (single source of truth)
    let sharedCoordinator: SharedAppCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var lastSharedBytesProcessed: Int64 = 0

    // MARK: - macOS-Specific ViewModels (backward compat for views)
    @Published var progressViewModel = ProgressViewModel()
    /// Mac-only volume access, backup-drive discovery, recents and drive speed.
    let volumeAccess: MacVolumeAccessModel
    /// Mac-only: a detected camera card becomes the source when allowed.
    let cameraAutoSource: MacCameraAutoSourceController
    /// The one job view model, owned by the shared coordinator.
    var photographerJobViewModel: PhotographerJobViewModel { sharedCoordinator.photographerJobViewModel }
    /// Mac-only SFTP off-site backups.
    let remoteBackups: MacRemoteBackupController
    var hostTrustPrompt: MacRemoteBackupController.HostTrustPrompt? { remoteBackups.hostTrustPrompt }

    // MARK: - Delegated State
    @Published var currentMode: AppMode = .copyAndVerify
    /// Mac-only benchmark estimate shown above Start.
    let estimate = TransferEstimateModel()
    var timeEstimate: TimeEstimate? { estimate.estimate }
    var isCalculatingEstimate: Bool { estimate.isCalculating }

    // MARK: - Computed Properties (delegated to SharedAppCoordinator)
    var isOperationInProgress: Bool { sharedCoordinator.isOperationInProgress }
    var completionState: CompletionState { sharedCoordinator.completionState }
    var results: [ResultRow] { sharedCoordinator.results }
    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify: return sourceURL != nil && !destinationURLs.isEmpty
        case .compareFolders: return leftURL != nil && rightURL != nil
        case .masterReport: return false
        }
    }
    // The selection lives in the shared coordinator.
    var sourceURL: URL? {
        get { sharedCoordinator.sourceURL }
        set { sharedCoordinator.sourceURL = newValue }
    }
    var destinationURLs: [URL] {
        get { sharedCoordinator.destinationURLs }
        set { sharedCoordinator.destinationURLs = newValue }
    }
    var leftURL: URL? {
        get { sharedCoordinator.leftURL }
        set { sharedCoordinator.leftURL = newValue }
    }
    var rightURL: URL? {
        get { sharedCoordinator.rightURL }
        set { sharedCoordinator.rightURL = newValue }
    }
    var sourceFolderInfo: EnhancedFolderInfo? { sharedCoordinator.sourceFolderInfo }
    var isAnalysingSource: Bool { sharedCoordinator.isAnalysingSource }
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
    /// The camera label lives (and is saved) in the shared coordinator.
    var cameraLabels: CameraLabelModel { sharedCoordinator.cameraLabels }
    var cameraLabelSettings: CameraLabelSettings {
        get { sharedCoordinator.cameraLabelSettings }
        set { sharedCoordinator.cameraLabelSettings = newValue }
    }
    /// Report settings live (and are saved) in the shared coordinator.
    var reportSettings: ReportPrefs {
        get { sharedCoordinator.reportSettings }
        set { sharedCoordinator.reportSettings = newValue }
    }

    // MARK: - Actions (delegated)
    func startOperation() {
        if currentMode == .copyAndVerify {
            let preflightReady = copyAndVerifyPreflightIsReady
            guard preflightReady else { return }
            if photographerJobViewModel.hasPreparedIngestAwaitingStart {
                guard photographerJobViewModel.isStartEligible(
                    preflightReady: preflightReady,
                    sourceURL: sourceURL,
                    destinationCount: destinationURLs.count,
                    verificationMode: verificationMode
                ) else { return }
            }
        }
        // Sync macOS VM state into SharedAppCoordinator
        sharedCoordinator.currentMode = currentMode
        // The job's folder recipe applies to this run only; the saved label
        // is left as the user set it.
        if currentMode == .copyAndVerify,
           photographerJobViewModel.hasPreparedIngestAwaitingStart,
           let renderedRecipe = photographerJobViewModel.renderedRecipe {
            sharedCoordinator.projectRunCameraSettings = PhotographerDestinationResolver.operationSettings(
                base: sharedCoordinator.cameraLabelSettings,
                renderedRecipe: renderedRecipe
            )
        } else {
            sharedCoordinator.projectRunCameraSettings = nil
        }
        configurePhotographerReportLifecycle()

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

    private var copyAndVerifyPreflightIsReady: Bool {
        guard let sourceURL,
              !destinationURLs.isEmpty,
              !isAnalysingSource else { return false }
        let destinations = destinationURLs
        let uniquePaths = Set(destinations.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        guard uniquePaths.count == destinations.count,
              destinations.allSatisfy({ destination in
                  !SafetyValidator.isProtectedSystemPath(destination)
                      && SafetyValidator.destinationSafetyIssue(source: sourceURL, destination: destination) == nil
              }) else { return false }
        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: sourceURL,
                destinations: destinations,
                settings: sharedCoordinator.cameraLabelSettings
            )
        } catch {
            return false
        }
        if let sourceSize = sourceFolderInfo?.totalSize {
            for destination in destinations {
                if let available = (try? destination.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity,
                   Int64(available) < sourceSize + Int64(100 * 1024 * 1024) {
                    return false
                }
            }
        }
        return true
    }

    private func makePhotographerReportContext() -> PhotographerReportContext? {
        guard currentMode == .copyAndVerify,
              photographerJobViewModel.hasPreparedIngestAwaitingStart,
              let job = photographerJobViewModel.activeJob,
              let card = photographerJobViewModel.activeCard,
              let analysis = photographerJobViewModel.preliminaryAnalysis else { return nil }
        let warnings = photographerJobViewModel.duplicateWarning.map { [$0.message] } ?? []
        return PhotographerReportContext(
            job: job,
            cardIngestID: card.id,
            analysis: analysis,
            verifiedDestinationCount: card.verifiedDestinationCount,
            warnings: warnings
        )
    }

    private func configurePhotographerReportLifecycle() {
        guard currentMode == .copyAndVerify,
              photographerJobViewModel.hasPreparedIngestAwaitingStart,
              let jobID = photographerJobViewModel.activeJob?.id,
              let cardID = photographerJobViewModel.activeCard?.id,
              photographerJobViewModel.preliminaryAnalysis != nil else {
            sharedCoordinator.photographerReportFinalizer = nil
            return
        }

        sharedCoordinator.photographerReportFinalizer = { [weak self, jobID, cardID] results in
            guard let self,
                  self.photographerJobViewModel.activeJob?.id == jobID,
                  self.photographerJobViewModel.activeCard?.id == cardID,
                  self.photographerJobViewModel.preliminaryAnalysis != nil,
                  let state = self.photographerJobViewModel.activeCard?.localState,
                  state == .copying || state == .verifying else {
                throw PhotographerReportError.cardNotReady
            }
            return try self.photographerJobViewModel.completeIngest(results: results)
        }
    }

    func cancelOperation() {
        sharedCoordinator.cancelOperation()
    }

    // MARK: - Remote backup bridge (forwards to MacRemoteBackupController)

    func selectRemoteProfile(_ profileID: UUID?) { remoteBackups.selectRemoteProfile(profileID) }
    func testRemoteProfile(_ profile: RemoteDestinationProfile) { remoteBackups.testRemoteProfile(profile) }
    func queueRemoteBackup(for cardIngestID: UUID) { remoteBackups.queueRemoteBackup(for: cardIngestID) }
    func startRemoteBackupScheduler() { remoteBackups.startRemoteBackupScheduler() }
    func runDueRemoteBackups() async { await remoteBackups.runDueRemoteBackups() }
    func confirmHostTrust(_ accepted: Bool) { remoteBackups.confirmHostTrust(accepted) }
    func pauseRemoteBackup(for cardIngestID: UUID) { remoteBackups.pauseRemoteBackup(for: cardIngestID) }
    func retryRemoteBackup(for cardIngestID: UUID) { remoteBackups.retryRemoteBackup(for: cardIngestID) }
    func cancelRemoteBackup(for cardIngestID: UUID) { remoteBackups.cancelRemoteBackup(for: cardIngestID) }

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

    // MARK: - Camera Detection (forwards to MacCameraAutoSourceController)
    func toggleCameraDetection(_ enabled: Bool) { cameraAutoSource.toggleCameraDetection(enabled) }
    func rescanForCameras() { cameraAutoSource.rescanForCameras() }

    // MARK: - Initialization
    /// `platformManager` defaults to the real macOS manager; tests inject one
    /// that does not present modal alerts.
    init(
        photographerJobViewModel: PhotographerJobViewModel? = nil,
        monitorsVolumes: Bool = true,
        platformManager: PlatformManager = MacOSPlatformManager.shared,
        remoteBackupQueue: RemoteBackupQueue? = nil,
        startRemoteScheduler: Bool = true,
        sharedCoordinator: SharedAppCoordinator? = nil
    ) {
        let shared: SharedAppCoordinator
        let remoteBackups: MacRemoteBackupController
        if sharedCoordinator != nil || photographerJobViewModel != nil {
            if let sharedCoordinator {
                // A test that builds the shared coordinator gives it the job
                // view model itself; there is only one.
                precondition(
                    photographerJobViewModel == nil || photographerJobViewModel === sharedCoordinator.photographerJobViewModel,
                    "Pass the job view model to SharedAppCoordinator, not to AppCoordinator"
                )
                shared = sharedCoordinator
            } else {
                shared = SharedAppCoordinator(
                    platformManager: platformManager,
                    photographerJobViewModel: photographerJobViewModel
                )
            }
            remoteBackups = MacRemoteBackupController(
                photographerJobViewModel: shared.photographerJobViewModel,
                results: { [weak shared] in shared?.results ?? [] },
                queue: remoteBackupQueue
            )
            if startRemoteScheduler { remoteBackups.startRemoteBackupScheduler() }
        } else {
            let store = CoreDataPhotographerJobStore(persistence: BitMatchPersistenceController.shared)
            let remoteBackupCoordinator = RemoteBackupCoordinator(store: store)
            let jobs = PhotographerJobViewModel(store: store, remoteBackupCoordinator: remoteBackupCoordinator)
            shared = SharedAppCoordinator(platformManager: platformManager, photographerJobViewModel: jobs)
            remoteBackups = MacRemoteBackupController.makeDefault(
                store: store,
                photographerJobViewModel: jobs,
                remoteBackupCoordinator: remoteBackupCoordinator,
                results: { [weak shared] in shared?.results ?? [] },
                startScheduler: startRemoteScheduler
            )
        }
        self.sharedCoordinator = shared
        self.remoteBackups = remoteBackups
        self.volumeAccess = MacVolumeAccessModel(shared: shared, enableVolumeMonitoring: monitorsVolumes)
        self.cameraAutoSource = MacCameraAutoSourceController(shared: shared, startMonitoring: monitorsVolumes)
        estimate.bind(to: shared)
        // The host-key alert and the estimate line read these companions
        // through this object.
        remoteBackups.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        estimate.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        setupProgressBindings()
        setupSharedCoordinatorBindings()
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
        NotificationCenter.default.publisher(for: .init("BitMatchQueuedTransferSelected"))
            .sink { [weak self] notification in
                guard let self, (notification.object as? SharedAppCoordinator) === self.sharedCoordinator else { return }
                self.currentMode = .copyAndVerify
            }.store(in: &cancellables)
        // Map SharedAppCoordinator progress → ProgressViewModel
        sharedCoordinator.$progress.compactMap { $0 }
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] prog in
                guard let self else { return }
                self.progressViewModel.setFileCountTotal(prog.totalFiles)
                self.progressViewModel.setPlannedTotalBytes(prog.totalBytes)
                self.progressViewModel.fileCountCompleted = prog.filesProcessed
                let destCount = self.sharedCoordinator.destinationURLs.count
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
                guard let self, self.currentMode == .copyAndVerify && !self.sharedCoordinator.isReplayingQueuedTransfer else { return }
                self.photographerJobViewModel.updateProgressStage(progress.currentStage)
            }
            .store(in: &cancellables)

        // Views read shared state through this object until they observe
        // SharedAppCoordinator directly (Task 9). Relayed on the next run-loop
        // turn, as the per-property relays it replaces were.
        sharedCoordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Map operation state for progress timer management
        sharedCoordinator.operationStatePublisher.sink { [weak self] state in
            guard let self else { return }
            switch state {
            case .inProgress, .copying, .verifying:
                self.progressViewModel.startProgressTracking()
                if self.progressViewModel.progressMessage == "Ready" {
                    self.progressViewModel.setProgressMessage("Preparing transfer…")
                }
                if self.currentMode == .copyAndVerify && !self.sharedCoordinator.isReplayingQueuedTransfer {
                    switch state {
                    case .inProgress, .copying:
                        self.photographerJobViewModel.beginIngest(
                            destinationCount: self.sharedCoordinator.destinationURLs.count,
                            sourceURL: self.sharedCoordinator.sourceURL,
                            verificationMode: self.verificationMode
                        )
                    case .verifying:
                        self.photographerJobViewModel.updateProgressStage(.verifying)
                    default:
                        break
                    }
                }
            case .completed(let info):
                self.progressViewModel.stopProgressTracking()
                self.lastSharedBytesProcessed = 0
                if self.currentMode == .copyAndVerify && !self.sharedCoordinator.isReplayingQueuedTransfer, !info.success {
                    self.photographerJobViewModel.operationFailed()
                }
            case .failed, .cancelled:
                self.progressViewModel.stopProgressTracking()
                self.lastSharedBytesProcessed = 0
                if self.currentMode == .copyAndVerify && !self.sharedCoordinator.isReplayingQueuedTransfer {
                    if state == .cancelled {
                        self.photographerJobViewModel.cancelIngest()
                    } else {
                        self.photographerJobViewModel.operationFailed()
                    }
                }
            default: break
            }
        }.store(in: &cancellables)

        photographerJobViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

    }
}
