// MacAppEnvironment.swift - builds the Mac app's state once
//
// SharedAppCoordinator is the only state owner, as on iPad and iPhone. The
// Mac adds four small companions that read from and write to it and keep no
// copy of its state: SFTP off-site backups (the thesis's named Mac
// exception), the drive-benchmark estimate, volume access and backup-drive
// discovery, and choosing a detected camera card as the source.
import SwiftUI

@MainActor
final class MacAppEnvironment: ObservableObject {
    let coordinator: SharedAppCoordinator
    let remoteBackups: MacRemoteBackupController
    let estimate: TransferEstimateModel
    let volumeAccess: MacVolumeAccessModel
    let cameraAutoSource: MacCameraAutoSourceController

    init(
        coordinator: SharedAppCoordinator,
        remoteBackups: MacRemoteBackupController,
        estimate: TransferEstimateModel = TransferEstimateModel(),
        monitorsVolumes: Bool = true
    ) {
        self.coordinator = coordinator
        self.remoteBackups = remoteBackups
        self.estimate = estimate
        self.volumeAccess = MacVolumeAccessModel(shared: coordinator, enableVolumeMonitoring: monitorsVolumes)
        self.cameraAutoSource = MacCameraAutoSourceController(shared: coordinator, startMonitoring: monitorsVolumes)
        estimate.bind(to: coordinator)
    }

    /// The app: the Core Data project store and its job view model, the
    /// coordinator on the real macOS services, and the SFTP queue with its
    /// scheduler running.
    static func make(platformManager: PlatformManager = MacOSPlatformManager.shared) -> MacAppEnvironment {
        let store = CoreDataPhotographerJobStore(persistence: BitMatchPersistenceController.shared)
        let remoteBackupCoordinator = RemoteBackupCoordinator(store: store)
        let jobs = PhotographerJobViewModel(store: store, remoteBackupCoordinator: remoteBackupCoordinator)
        let coordinator = SharedAppCoordinator(platformManager: platformManager, photographerJobViewModel: jobs)
        let remoteBackups = MacRemoteBackupController.makeDefault(
            store: store,
            photographerJobViewModel: jobs,
            remoteBackupCoordinator: remoteBackupCoordinator,
            results: { [weak coordinator] in coordinator?.results ?? [] }
        )
        return MacAppEnvironment(coordinator: coordinator, remoteBackups: remoteBackups)
    }

    /// Tests and previews: the given coordinator, no volume or camera
    /// monitoring, no SFTP queue or scheduler, and no drive benchmark.
    static func makeForTesting(coordinator: SharedAppCoordinator) -> MacAppEnvironment {
        MacAppEnvironment(
            coordinator: coordinator,
            remoteBackups: MacRemoteBackupController(
                photographerJobViewModel: coordinator.photographerJobViewModel,
                results: { [weak coordinator] in coordinator?.results ?? [] }
            ),
            estimate: TransferEstimateModel { _, _, _, _ in nil },
            monitorsVolumes: false
        )
    }
}

extension View {
    /// The Mac companions views further down read as environment objects.
    /// Apply at every hosting root (the main window).
    func macCompanions(_ environment: MacAppEnvironment) -> some View {
        self
            .environmentObject(environment.remoteBackups)
            .environmentObject(environment.volumeAccess)
            .environmentObject(environment.estimate)
    }
}
