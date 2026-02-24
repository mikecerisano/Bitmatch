// DependencyContainer.swift - Centralized dependency injection container
// Phase 3: Replace .shared singletons with injectable dependencies
import Foundation

/// Centralized container for app-wide service dependencies
/// Replaces scattered .shared singletons with a single injectable source of truth
@MainActor
final class DependencyContainer {
    // MARK: - Singleton (for gradual migration)
    static let shared = DependencyContainer()

    // MARK: - Services
    let folderInfoService: FolderInfoService
    let checksumService: SharedChecksumService
    let checksumCache: SharedChecksumCache
    let backgroundTaskService: IOSBackgroundTaskService

    // MARK: - Initialization

    init(
        folderInfoService: FolderInfoService? = nil,
        checksumService: SharedChecksumService? = nil,
        checksumCache: SharedChecksumCache? = nil,
        backgroundTaskService: IOSBackgroundTaskService? = nil
    ) {
        self.folderInfoService = folderInfoService ?? FolderInfoService.shared
        self.checksumService = checksumService ?? SharedChecksumService.shared
        self.checksumCache = checksumCache ?? SharedChecksumCache.shared
        self.backgroundTaskService = backgroundTaskService ?? IOSBackgroundTaskService.shared
    }

    /// Create a container with mock services for testing
    static func forTesting(
        folderInfoService: FolderInfoService? = nil,
        checksumService: SharedChecksumService? = nil,
        checksumCache: SharedChecksumCache? = nil,
        backgroundTaskService: IOSBackgroundTaskService? = nil
    ) -> DependencyContainer {
        return DependencyContainer(
            folderInfoService: folderInfoService,
            checksumService: checksumService,
            checksumCache: checksumCache,
            backgroundTaskService: backgroundTaskService
        )
    }
}
