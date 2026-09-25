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

    // MARK: - macOS-Specific ViewModels (backward compat for views)
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
    /// The mode lives in the shared coordinator (one mode, one lock).
    var currentMode: AppMode {
        get { sharedCoordinator.currentMode }
        set { sharedCoordinator.currentMode = newValue }
    }
    /// Mac-only benchmark estimate shown above Start.
    let estimate = TransferEstimateModel()
    var timeEstimate: TimeEstimate? { estimate.estimate }
    var isCalculatingEstimate: Bool { estimate.isCalculating }

    // MARK: - Computed Properties (delegated to SharedAppCoordinator)
    var isOperationInProgress: Bool { sharedCoordinator.isOperationInProgress }
    var completionState: CompletionState { sharedCoordinator.completionState }
    var results: [ResultRow] { sharedCoordinator.results }
    var canStartOperation: Bool { sharedCoordinator.canStartOperation }
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
    /// Smoothed progress, owned by the shared coordinator. Views observe it
    /// directly; it is not relayed through this object.
    var progressPresentation: ProgressPresentationModel { sharedCoordinator.progressPresentation }
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
    /// The shared Start: a prepared project card, an ordinary transfer when
    /// ready, or the compare.
    func startOperation() {
        Task { @MainActor in await sharedCoordinator.startCurrentMode() }
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
        sharedCoordinator.switchMode(to: mode)
    }

    func resetForNewOperation() {
        sharedCoordinator.resetForNewOperation()
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
        setupSharedCoordinatorBindings()
    }

    // MARK: - Shared Core Bindings
    private func setupSharedCoordinatorBindings() {
        // Views read shared state through this object until they observe
        // SharedAppCoordinator directly (Task 9). Relayed on the next run-loop
        // turn, as the per-property relays it replaced were.
        sharedCoordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
