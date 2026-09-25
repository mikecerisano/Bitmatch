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
    @Published var fileSelectionViewModel: FileSelectionViewModel
    @Published var cameraLabelViewModel = CameraLabelViewModel()
    @Published var settingsViewModel = SettingsViewModel()
    @Published var cameraDetectionService = CameraCardDetectionService()
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
        if currentMode == .copyAndVerify {
            let preflightReady = copyAndVerifyPreflightIsReady
            guard preflightReady else { return }
            if photographerJobViewModel.hasPreparedIngestAwaitingStart {
                guard photographerJobViewModel.isStartEligible(
                    preflightReady: preflightReady,
                    sourceURL: fileSelectionViewModel.sourceURL,
                    destinationCount: fileSelectionViewModel.destinationURLs.count,
                    verificationMode: verificationMode
                ) else { return }
            }
        }
        // Sync macOS VM state into SharedAppCoordinator
        sharedCoordinator.currentMode = currentMode
        var operationSettings = cameraLabelViewModel.destinationLabelSettings
        if photographerJobViewModel.hasPreparedIngestAwaitingStart,
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
        guard let sourceURL = fileSelectionViewModel.sourceURL,
              !fileSelectionViewModel.destinationURLs.isEmpty,
              !fileSelectionViewModel.isFetchingSourceInfo else { return false }
        let destinations = fileSelectionViewModel.destinationURLs
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
                settings: cameraLabelViewModel.destinationLabelSettings
            )
        } catch {
            return false
        }
        if let sourceSize = fileSelectionViewModel.sourceFolderInfo?.totalSize {
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
    /// `mode` is passed when the verification mode is about to change, since
    /// `$verificationMode` publishes before the new value is stored.
    func updateTimeEstimate(mode: VerificationMode? = nil) {
        estimate.update(
            source: fileSelectionViewModel.sourceURL,
            destinations: fileSelectionViewModel.destinationURLs,
            totalBytes: fileSelectionViewModel.sourceFolderInfo?.totalSize,
            mode: mode ?? verificationMode
        )
    }

    // MARK: - Initialization
    /// `platformManager` defaults to the real macOS manager; tests inject one
    /// that does not present modal alerts.
    init(
        photographerJobViewModel: PhotographerJobViewModel? = nil,
        fileSelectionViewModel: FileSelectionViewModel? = nil,
        platformManager: PlatformManager = MacOSPlatformManager.shared,
        remoteBackupQueue: RemoteBackupQueue? = nil,
        startRemoteScheduler: Bool = true,
        sharedCoordinator: SharedAppCoordinator? = nil
    ) {
        self.fileSelectionViewModel = fileSelectionViewModel ?? FileSelectionViewModel()
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
        // The host-key alert and the estimate line read these companions
        // through this object.
        remoteBackups.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        estimate.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // A new verification mode changes the estimate (verify passes).
        shared.$verificationMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in self?.updateTimeEstimate(mode: mode) }
            .store(in: &cancellables)
        setupFileSelectionBindings()
        setupProgressBindings()
        setupSharedCoordinatorBindings()
        setupCameraDetection()
    }

    private func setupFileSelectionBindings() {
        // Keep retained comparison evidence tied to the folders shown on Mac,
        // including selections made after a comparison has finished.
        fileSelectionViewModel.$leftURL
            .sink { [weak self] in self?.sharedCoordinator.leftURL = $0 }
            .store(in: &cancellables)
        fileSelectionViewModel.$rightURL
            .sink { [weak self] in self?.sharedCoordinator.rightURL = $0 }
            .store(in: &cancellables)

        // Camera detection with memory when source changes. `dropFirst()`
        // skips the synchronous replay Combine delivers immediately upon
        // subscribing to `$sourceURL`; without it, every AppCoordinator
        // init reports a spurious "source changed to nil" to the
        // photographer job view model and permanently invalidates any
        // already-prepared card's source signature before the user has
        // touched anything.
        fileSelectionViewModel.$sourceURL.dropFirst().sink { [weak self] url in
            if let url = url { self?.cameraLabelViewModel.detectCameraWithMemory(at: url) }
            else { self?.cameraLabelViewModel.clearCameraLabel() }
            self?.photographerJobViewModel.sourceDidChange(to: url)
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
        NotificationCenter.default.publisher(for: .init("BitMatchQueuedTransferSelected"))
            .sink { [weak self] notification in
                guard let self, (notification.object as? SharedAppCoordinator) === self.sharedCoordinator else { return }
                self.currentMode = .copyAndVerify
                self.fileSelectionViewModel.sourceURL = self.sharedCoordinator.sourceURL
                self.fileSelectionViewModel.destinationURLs = self.sharedCoordinator.destinationURLs
                self.cameraLabelViewModel.destinationLabelSettings = self.sharedCoordinator.cameraLabelSettings
            }.store(in: &cancellables)
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
                guard let self, self.currentMode == .copyAndVerify && !self.sharedCoordinator.isReplayingQueuedTransfer else { return }
                self.photographerJobViewModel.updateProgressStage(progress.currentStage)
            }
            .store(in: &cancellables)

        // Refresh compare results when a comparison publishes retained differences.
        sharedCoordinator.$lastCompareStats
            .map { _ in () }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
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

        Publishers.MergeMany(
            sharedCoordinator.$isOperationInProgress.map { _ in () }.eraseToAnyPublisher(),
            sharedCoordinator.operationStatePublisher.map { _ in () }.eraseToAnyPublisher(),
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
                guard let self, self.settingsViewModel.prefs.enableAutoCameraDetection else { return }
                let sourceURL = cameraCard.mediaPath
                let shouldSelect = AutomaticSourceSelectionPolicy.shouldSelect(
                    automaticSelectionEnabled: self.settingsViewModel.prefs.autoPopulateSource,
                    hasExistingSource: self.fileSelectionViewModel.sourceURL != nil,
                    isReadable: FileManager.default.isReadableFile(atPath: sourceURL.path)
                )
                guard shouldSelect else {
                    SharedLogger.info("Detected camera card is available, but BitMatch did not auto-select it without readable access.", category: .transfer)
                    return
                }
                self.fileSelectionViewModel.sourceURL = sourceURL
            }.store(in: &cancellables)

        if settingsViewModel.prefs.enableAutoCameraDetection {
            cameraDetectionService.startMonitoring()
        }
    }
}
