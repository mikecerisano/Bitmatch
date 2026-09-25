// DestinationDismissalTests.swift
import Foundation
import Testing
@testable import BitMatch

/// Rediscovery must not undo an explicit destination removal. A removed
/// drive stays out while it remains visible to discovery; disappearing
/// (unplug) and reappearing treats it as a new arrival again.
@MainActor
struct DestinationDismissalTests {
    /// Discovery writes through the shared coordinator, which owns the backups.
    private func makeModel() -> (MacVolumeAccessModel, SharedAppCoordinator) {
        let shared = SharedAppCoordinator(
            platformManager: RecordingPlatformManager(fileOperations: RecordingFileOperations()),
            projectStore: InMemoryPhotographerJobStore()
        )
        return (MacVolumeAccessModel(shared: shared, enableVolumeMonitoring: false), shared)
    }

    private func drive(at path: String) -> VolumeMonitorService.DetectedVolume {
        VolumeMonitorService.DetectedVolume(
            url: URL(fileURLWithPath: path),
            name: "Drive",
            capacity: 1_000,
            available: 500,
            type: .backupDrive,
            cameraInfo: nil,
            devicePath: path
        )
    }

    @Test func removedDestinationIsNotReaddedByRediscovery() async throws {
        #if os(macOS)
        let (viewModel, shared) = makeModel()
        let drive = drive(at: "/Volumes/DISMISSED")

        viewModel.handleBackupDrivesUpdate([drive])
        #expect(shared.destinationURLs.map(\.path) == [drive.url.path])

        viewModel.removeDestination(drive.url)
        #expect(shared.destinationURLs.isEmpty)

        // Same drive still visible to discovery: must stay out.
        viewModel.handleBackupDrivesUpdate([drive])
        #expect(shared.destinationURLs.isEmpty)
        #else
        #expect(true)
        #endif
    }

    @Test func repluggedDriveIsTreatedAsNewArrival() async throws {
        #if os(macOS)
        let (viewModel, shared) = makeModel()
        let drive = drive(at: "/Volumes/REPLUGGED")

        viewModel.handleBackupDrivesUpdate([drive])
        viewModel.removeDestination(drive.url)

        // Drive disappears (unplugged): dismissal expires.
        viewModel.handleBackupDrivesUpdate([])
        // Drive reappears: treated as a new arrival, auto-added again.
        viewModel.handleBackupDrivesUpdate([drive])
        #expect(shared.destinationURLs.map(\.path) == [drive.url.path])
        #else
        #expect(true)
        #endif
    }

    @Test func explicitReaddClearsDismissal() async throws {
        #if os(macOS)
        let (viewModel, shared) = makeModel()
        let drive = drive(at: "/Volumes/READDED")

        viewModel.handleBackupDrivesUpdate([drive])
        viewModel.removeDestination(drive.url)
        viewModel.addDestination(drive.url)

        // User changed their mind: later updates must not drop it, and the
        // dismissal must be forgotten.
        viewModel.handleBackupDrivesUpdate([drive])
        #expect(shared.destinationURLs.map(\.path) == [drive.url.path])
        #else
        #expect(true)
        #endif
    }
}
