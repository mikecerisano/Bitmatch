import Foundation
import Testing
@testable import BitMatch

/// The Mac companions all work on the one shared coordinator and its one
/// job view model; none keeps its own copy.
@MainActor
struct MacAppEnvironmentTests {
    private func makeEnvironment() throws -> (MacAppEnvironment, CoordinatorFolders) {
        let folders = try CoordinatorFolders()
        let coordinator = SharedAppCoordinator(
            platformManager: RecordingPlatformManager(fileOperations: RecordingFileOperations()),
            transferJournal: LocalTransferJournal(fileURL: folders.journalURL),
            projectStore: InMemoryPhotographerJobStore()
        )
        return (MacAppEnvironment.makeForTesting(coordinator: coordinator), folders)
    }

    /// Plant: in `MacAppEnvironment.makeForTesting`, give the controller
    /// `PhotographerJobViewModel(store: InMemoryPhotographerJobStore())`
    /// (or, in `make()`, build a second job view model for it).
    @Test func sftpControllerUsesTheCoordinatorsJobViewModel() throws {
        let (environment, folders) = try makeEnvironment()
        defer { folders.cleanup() }

        #expect(environment.remoteBackups.photographerJobViewModel === environment.coordinator.photographerJobViewModel)
    }

    /// Backups added through the Mac volume model land in the shared
    /// selection, and the estimate follows it.
    /// Plant: in `MacVolumeAccessModel.addDestination`, replace
    /// `shared?.addDestination(url, origin: .userChoice, facts: volumeFacts)`
    /// with `nil as String?`.
    @Test func volumeModelWritesThroughTheSharedSelection() throws {
        let (environment, folders) = try makeEnvironment()
        defer { folders.cleanup() }

        environment.volumeAccess.addDestination(folders.primary)

        #expect(environment.coordinator.destinationURLs == [folders.primary])
    }

    /// Plant: in `MacAppEnvironment.init`, delete `estimate.bind(to: coordinator)`.
    @Test func estimateFollowsTheSharedSelection() async throws {
        let folders = try CoordinatorFolders()
        defer { folders.cleanup() }
        let coordinator = SharedAppCoordinator(
            platformManager: RecordingPlatformManager(fileOperations: RecordingFileOperations()),
            transferJournal: LocalTransferJournal(fileURL: folders.journalURL),
            projectStore: InMemoryPhotographerJobStore()
        )
        let environment = MacAppEnvironment(
            coordinator: coordinator,
            remoteBackups: MacRemoteBackupController(
                photographerJobViewModel: coordinator.photographerJobViewModel,
                results: { [] }
            ),
            estimate: TransferEstimateModel { _, destinations, bytes, _ in
                TimeEstimate(totalSeconds: Double(bytes), copySeconds: 0, verifySeconds: 0,
                             readSpeedMBps: 1, writeSpeedMBps: 1, destinationCount: destinations.count)
            },
            monitorsVolumes: false
        )
        environment.coordinator.destinationURLs = [folders.primary]
        environment.coordinator.sourceURL = folders.source

        // The source holds one 4-byte file.
        #expect(await waitUntil(timeout: .seconds(5)) { environment.estimate.estimate?.totalSeconds == 4 })
        #expect(environment.estimate.estimate?.destinationCount == 1)
    }
}
