import Foundation

/// The platform-neutral project boundary for configuring an optional remote
/// destination. macOS can perform uploads; other devices can safely retain
/// the destination choice without pretending an upload occurred.
@MainActor
protocol ProjectRemoteCoordinator {
    @discardableResult
    func selectRemoteProfile(_ profileID: UUID?, for jobID: UUID) throws -> PhotographerJob
    func queueRemoteBackup(for cardIngestID: UUID, in jobID: UUID, results: [ResultRow]) throws -> [RemoteQueueItem]
    func pauseRemoteBackup(for cardIngestID: UUID, in jobID: UUID) throws -> [RemoteQueueItem]
    func retryRemoteBackup(for cardIngestID: UUID, in jobID: UUID) throws -> [RemoteQueueItem]
}

enum ProjectRemoteCoordinatorError: LocalizedError, Equatable {
    case missingJob
    case missingProfile
    case remoteUploadsRequireMac
    case manifestUnavailable

    var errorDescription: String? {
        switch self {
        case .missingJob:
            return "Choose a project before setting a remote destination."
        case .missingProfile:
            return "The selected remote backup destination no longer exists."
        case .remoteUploadsRequireMac:
            return "Remote backup is configured. Continue the upload from BitMatch on Mac."
        case .manifestUnavailable:
            return "The saved remote backup manifest is unavailable."
        }
    }
}

/// iPhone and iPad preserve project routing and destination intent, but do
/// not claim to run an SSH-backed upload in the background.
@MainActor
final class UnavailableRemoteProjectCoordinator: ProjectRemoteCoordinator {
    private let store: any PhotographerJobStore
    private let now: () -> Date

    init(store: any PhotographerJobStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    func selectRemoteProfile(_ profileID: UUID?, for jobID: UUID) throws -> PhotographerJob {
        guard var job = try store.jobs().first(where: { $0.id == jobID }) else {
            throw ProjectRemoteCoordinatorError.missingJob
        }
        if let profileID {
            guard try store.profiles().contains(where: { $0.id == profileID }) else {
                throw ProjectRemoteCoordinatorError.missingProfile
            }
            job.remoteBackupConfiguration = RemoteBackupConfiguration(
                isEnabled: true,
                destinationProfileID: profileID
            )
        } else {
            job.remoteBackupConfiguration = RemoteBackupConfiguration()
        }
        job.updatedAt = now()
        try store.save(job)
        return job
    }

    func queueRemoteBackup(for _: UUID, in _: UUID, results _: [ResultRow]) throws -> [RemoteQueueItem] {
        throw ProjectRemoteCoordinatorError.remoteUploadsRequireMac
    }

    func pauseRemoteBackup(for _: UUID, in _: UUID) throws -> [RemoteQueueItem] {
        throw ProjectRemoteCoordinatorError.remoteUploadsRequireMac
    }

    func retryRemoteBackup(for _: UUID, in _: UUID) throws -> [RemoteQueueItem] {
        throw ProjectRemoteCoordinatorError.remoteUploadsRequireMac
    }
}
