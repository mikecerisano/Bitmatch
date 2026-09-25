// Core/ViewModels/MacVolumeAccessModel.swift
//
// The Mac-only half of the old file-selection view model: the volume
// monitor and backup-drive discovery, /Volumes bookmarks, recent folders,
// last-used backups and drive speed. The selection itself (source, backups,
// compare folders and their folder info) lives in SharedAppCoordinator;
// this model reads it and writes changes through it.
import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

@MainActor
final class MacVolumeAccessModel: ObservableObject {
    // MARK: - Published Properties
    @Published var recentFolders: [URL] = []

    // Auto-detected volumes
    @Published var detectedCameraCards: [VolumeMonitorService.DetectedVolume] = []
    @Published var detectedBackupDrives: [VolumeMonitorService.DetectedVolume] = []

    // MARK: - Private Properties
    private weak var shared: SharedAppCoordinator?
    private let lastDestinationsKey = "lastUsedDestinations"
    private let maxRememberedDestinations = 5
    private let recentFoldersListKey = "recentFoldersList"
    var volumeMonitor = VolumeMonitorService.shared
    private var cancellables = Set<AnyCancellable>()
    /// Track active security-scoped resource URLs to prevent leaks (Bug 2 fix)
    private var activeSecurityScopes = Set<URL>()
    /// Destination paths the user explicitly removed. Discovery auto-add
    /// skips these until the drive disappears (unplug) or the user re-adds
    /// it, so rediscovery never undoes a deliberate removal.
    private var dismissedDestinationPaths = Set<String>()

    private var sourceURL: URL? { shared?.sourceURL }
    private var destinationURLs: [URL] { shared?.destinationURLs ?? [] }

    // MARK: - Initialization
    init(shared: SharedAppCoordinator, enableVolumeMonitoring: Bool = true) {
        self.shared = shared
        loadRecentFolders()
        // Decision S-3: before anything can overwrite the saved list, put
        // back last time's backups, but only if every one is still mounted.
        // The real app only (tests build the model without monitoring).
        if enableVolumeMonitoring {
            restoreLastDestinations()
        }
        observeSelection(of: shared)
        if enableVolumeMonitoring {
            setupVolumeMonitoring()
            loadSavedBookmarks()
        }
    }

    /// Recents and last-used backups follow the shared selection. `$x`
    /// publishes the new value before it is stored, so the sinks use it.
    private func observeSelection(of shared: SharedAppCoordinator) {
        shared.$sourceURL.dropFirst()
            .sink { [weak self] url in self?.saveRecentFolder(url, key: "recentSource") }
            .store(in: &cancellables)
        shared.$leftURL.dropFirst()
            .sink { [weak self] url in self?.saveRecentFolder(url, key: "recentLeft") }
            .store(in: &cancellables)
        shared.$rightURL.dropFirst()
            .sink { [weak self] url in self?.saveRecentFolder(url, key: "recentRight") }
            .store(in: &cancellables)
        shared.$destinationURLs.dropFirst()
            .sink { [weak self] urls in
                if !urls.isEmpty { self?.saveLastDestinations(urls) }
            }
            .store(in: &cancellables)
    }

    deinit {
        // stopAccessingSecurityScopedResource is safe to call from any thread
        for url in activeSecurityScopes {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Release all active security-scoped resources to prevent leaks
    func stopAllSecurityScopes() {
        for url in activeSecurityScopes {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopes.removeAll()
    }

    private func trackSecurityScope(_ url: URL) {
        activeSecurityScopes.insert(url)
    }
    
    // MARK: - Volume Monitoring Setup
    private func setupVolumeMonitoring() {
        // Monitor camera cards
        volumeMonitor.$availableCameraCards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cards in
                self?.detectedCameraCards = cards
                self?.handleCameraCardsUpdate(cards)
            }
            .store(in: &cancellables)
        
        // Monitor backup drives  
        volumeMonitor.$availableBackupDrives
            .receive(on: DispatchQueue.main)
            .sink { [weak self] drives in
                self?.detectedBackupDrives = drives
                self?.handleBackupDrivesUpdate(drives)
            }
            .store(in: &cancellables)
    }
    
    private func handleCameraCardsUpdate(_ cards: [VolumeMonitorService.DetectedVolume]) {
        // Check if current source is still available
        if let sourceURL = sourceURL {
            let sourceStillExists = cards.contains { $0.url.path == sourceURL.path }
            if !sourceStillExists && FileManager.default.fileExists(atPath: sourceURL.path) == false {
                SharedLogger.info("Selected source volume was removed: \(sourceURL.lastPathComponent)", category: .transfer)
                shared?.sourceURL = nil
            }
        }
        
        // Volume discovery only updates the available-card list. Choosing a
        // source belongs to the explicit auto-source policy in
        // MacCameraAutoSourceController, which first proves the card is readable.
    }
    
    /// Internal (not private) so tests can drive the discovery policy
    /// without fabricating volume-monitor notifications.
    func handleBackupDrivesUpdate(_ drives: [VolumeMonitorService.DetectedVolume]) {
        // Check if any current destinations are no longer available
        let driveURLs = Set(drives.map { $0.url.path })
        let removedDestinations = destinationURLs.filter { destination in
            !driveURLs.contains(destination.path) && !FileManager.default.fileExists(atPath: destination.path)
        }

        for removed in removedDestinations {
            SharedLogger.info("Auto-removing unavailable destination: \(removed.lastPathComponent)", category: .transfer)
            removeDestination(removed)
        }

        // A dismissal expires when its drive disappears from discovery:
        // an unplug/replug cycle is a new arrival, not a resurrection.
        dismissedDestinationPaths = dismissedDestinationPaths.filter { driveURLs.contains($0) }

        // Auto-add new backup drives as destinations, but never undo an
        // explicit removal while the drive is still present.
        for drive in drives {
            if !destinationURLs.contains(drive.url) && !dismissedDestinationPaths.contains(drive.url.path) {
                addDestination(drive.url)
                SharedLogger.info("Auto-added backup drive: \(drive.displayName)", category: .transfer)
            }
        }
    }

    // MARK: - Public Methods
    /// Adds a backup through the shared coordinator (which refuses the same
    /// folder twice) and forgets any earlier dismissal of it.
    func addDestination(_ url: URL) {
        guard !destinationURLs.contains(url) else { return }
        // An explicit add overrides any earlier dismissal.
        dismissedDestinationPaths.remove(url.path)
        shared?.addDestination(url)
        saveRecentFolder(url, key: "recentDestination")
    }

    /// Removes a backup and remembers the dismissal, so discovery does not
    /// add the same drive back while it stays plugged in.
    func removeDestination(_ url: URL) {
        dismissedDestinationPaths.insert(url.path)
        shared?.removeDestinationFolder(url)
    }

    func removeAutoDetectedCameraCard(_ volume: VolumeMonitorService.DetectedVolume) {
        // If this was our auto-selected source, clear it
        if sourceURL == volume.url {
            shared?.sourceURL = nil
        }
        
        // Remove from volume monitor (user doesn't want to see this one)
        volumeMonitor.removeCameraCard(volume)
    }
    
    func removeAutoDetectedBackupDrive(_ volume: VolumeMonitorService.DetectedVolume) {
        // Remove from destinations if present
        removeDestination(volume.url)
        
        // Remove from volume monitor (user doesn't want to see this one)
        volumeMonitor.removeBackupDrive(volume)
    }
    
    // Manual test function for debugging
    func testVolumeDetection() {
        SharedLogger.debug("Testing volume detection manually...", category: .transfer)
        let testVolumes = [
            URL(fileURLWithPath: "/Volumes/Untitled"),
            URL(fileURLWithPath: "/Volumes/T9"),
            URL(fileURLWithPath: "/Volumes/T9/FUJI XT30")
        ]

        for url in testVolumes {
            if FileManager.default.fileExists(atPath: url.path) {
                SharedLogger.debug("Testing volume: \(url.path)", category: .transfer)

                // Test camera detection specifically
                let cameraType = CameraDetectionOrchestrator.shared.detectCamera(at: url)
                SharedLogger.debug("Camera detection result: \(cameraType ?? "None")", category: .transfer)

                // Test specific Fuji detection
                if let fujiResult = FujiDetectionService.shared.detectFujiCamera(at: url) {
                    SharedLogger.debug("Fuji detection: \(fujiResult)", category: .transfer)
                } else {
                    SharedLogger.debug("No Fuji files found", category: .transfer)
                }

                volumeMonitor.forceAnalyzeVolume(at: url)
            }
        }
    }
    
    @MainActor
    func requestVolumeAccess() {
        #if os(macOS)
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.directoryURL = URL(fileURLWithPath: "/")
        openPanel.title = "Grant Access to All Volumes"
        openPanel.message = "Select the 'Volumes' folder to enable automatic detection of all camera cards and external drives. This is a one-time permission that will work for all future cards and drives."
        
        // Pre-select the /Volumes directory
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        openPanel.directoryURL = volumesURL
        
        openPanel.begin { [weak self] response in
            guard response == .OK, let selectedURL = openPanel.urls.first else { return }

            SharedLogger.info("Granted access to: \(selectedURL.path)", category: .transfer)
            
            // Store security-scoped bookmark for the selected directory
            do {
                #if os(macOS)
                // Request read-write access to /Volumes so we can write to external drives
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = []
                #endif
                
                let bookmarkData = try selectedURL.bookmarkData(
                    options: bookmarkOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                // Security 17: store bookmark in Keychain instead of UserDefaults
                let key = "volumesDirectoryBookmark"
                _ = KeychainHelper.save(bookmarkData, forKey: key)
                UserDefaults.standard.set(selectedURL.path, forKey: "volumesDirectoryPath")

                SharedLogger.info("Saved volumes directory bookmark for: \(selectedURL.path)", category: .transfer)

                // Start accessing the security-scoped resource immediately
                if selectedURL.startAccessingSecurityScopedResource() {
                    self?.trackSecurityScope(selectedURL)
                    SharedLogger.info("Started accessing volumes directory: \(selectedURL.path)", category: .transfer)

                    // Trigger a fresh volume scan
                    self?.volumeMonitor.refreshVolumes()
                }

            } catch {
                SharedLogger.error("Failed to create bookmark for \(selectedURL.path): \(error)", category: .transfer)
            }
        }
        #else
        // iOS doesn't have NSOpenPanel - volume access is handled differently
        SharedLogger.warning("Volume access request not available on iOS", category: .transfer)
        #endif
    }
    
    func loadSavedBookmarks() {
        let defaults = UserDefaults.standard
        
        // Security 17: load bookmark from Keychain (fall back to UserDefaults for migration)
        let bookmarkData = KeychainHelper.load(forKey: "volumesDirectoryBookmark") ?? defaults.data(forKey: "volumesDirectoryBookmark")
        if let bookmarkData = bookmarkData {
            do {
                var isStale = false
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: resolveOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if !isStale && FileManager.default.fileExists(atPath: url.path) {
                    SharedLogger.info("Restored volumes directory bookmark: \(url.path)", category: .transfer)

                    // Start accessing the security-scoped resource
                    if url.startAccessingSecurityScopedResource() {
                        trackSecurityScope(url)
                        SharedLogger.info("Started accessing volumes directory: \(url.path)", category: .transfer)
                        // Trigger volume scan; specific write checks happen when starting a copy
                        volumeMonitor.refreshVolumes()
                        // Don't stop accessing - we want persistent access
                        return // We have volumes access, no need to check individual bookmarks
                    }
                } else {
                    SharedLogger.debug("Removing stale volumes directory bookmark", category: .transfer)
                    KeychainHelper.delete(forKey: "volumesDirectoryBookmark")
                    defaults.removeObject(forKey: "volumesDirectoryBookmark")
                    defaults.removeObject(forKey: "volumesDirectoryPath")
                }
            } catch {
                SharedLogger.error("Failed to resolve volumes directory bookmark: \(error)", category: .transfer)
                KeychainHelper.delete(forKey: "volumesDirectoryBookmark")
                defaults.removeObject(forKey: "volumesDirectoryBookmark")
                defaults.removeObject(forKey: "volumesDirectoryPath")
            }
        }
        
        // Fallback: Check for individual volume bookmarks (legacy support)
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix("bookmark_"), let bookmarkData = defaults.data(forKey: key) {
                do {
                    var isStale = false
                    #if os(macOS)
                    let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                    #else
                    let resolveOptions: URL.BookmarkResolutionOptions = []
                    #endif
                    
                    let url = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: resolveOptions,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    if !isStale && FileManager.default.fileExists(atPath: url.path) {
                        SharedLogger.info("Restored individual bookmark for: \(url.lastPathComponent)", category: .transfer)

                        // Start accessing the security-scoped resource
                        if url.startAccessingSecurityScopedResource() {
                            trackSecurityScope(url)
                            SharedLogger.info("Started accessing: \(url.path)", category: .transfer)

                            // Analyze the volume
                            volumeMonitor.forceAnalyzeVolume(at: url)
                        }
                    } else {
                        SharedLogger.debug("Removing stale bookmark for: \(key)", category: .transfer)
                        defaults.removeObject(forKey: key)
                    }
                } catch {
                    SharedLogger.error("Failed to resolve bookmark \(key): \(error)", category: .transfer)
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }
    
    var hasVolumeAccess: Bool {
        return KeychainHelper.load(forKey: "volumesDirectoryBookmark") != nil
            || UserDefaults.standard.data(forKey: "volumesDirectoryBookmark") != nil
    }
    
    // MARK: - Smart Defaults Methods
    func saveLastDestinations(_ urls: [URL]) {
        let paths = urls.prefix(maxRememberedDestinations).map { $0.path }
        UserDefaults.standard.set(paths, forKey: lastDestinationsKey)
    }
    
    /// Last time's backups, all or nothing (`LastBackupsRestorePolicy`):
    /// empty when any of them is not mounted now.
    func loadLastDestinations() -> [URL] {
        LastBackupsRestorePolicy.backupsToRestore(
            savedPaths: UserDefaults.standard.stringArray(forKey: lastDestinationsKey) ?? [],
            exists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    /// Called once at launch, while no backup is chosen yet.
    func restoreLastDestinations() {
        guard destinationURLs.isEmpty else { return }
        for dest in loadLastDestinations() {
            shared?.addDestination(dest)
        }
    }
    
    // MARK: - Volume Space Helpers
    func formattedAvailableSpace(for url: URL) -> String? {
        do {
            let rv = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let available = rv.volumeAvailableCapacity {
                return ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)
            }
        } catch { }
        return nil
    }
    
    // MARK: - Recent Folders Management
    private func saveRecentFolder(_ url: URL?, key: String) {
        guard let url = url else { return }
        UserDefaults.standard.set(url.path, forKey: key)
        updateRecentFolders()
    }
    
    private func loadRecentFolders() {
        var folders: [URL] = []
        
        // Load from individual keys
        let keys = ["recentLeft", "recentRight", "recentSource", "recentDestination"]
        for key in keys {
            if let path = UserDefaults.standard.string(forKey: key) {
                folders.append(URL(fileURLWithPath: path))
            }
        }
        
        // Load from list
        if let recentPaths = UserDefaults.standard.stringArray(forKey: recentFoldersListKey) {
            for path in recentPaths {
                folders.append(URL(fileURLWithPath: path))
            }
        }
        
        // Filter existing folders and remove duplicates
        let uniqueFolders = Array(Set(folders.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }))
        recentFolders = Array(uniqueFolders.prefix(10))
    }
    
    private func updateRecentFolders() {
        loadRecentFolders()
        let paths = recentFolders.map { $0.path }
        UserDefaults.standard.set(paths, forKey: recentFoldersListKey)
    }
    
    // MARK: - Smart Drive Detection
    func detectDriveSpeed(for url: URL) -> DriveSpeed {
        // Quick detection based on volume characteristics
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .volumeIsLocalKey,
                .volumeIsRemovableKey,
                .volumeSupportsFileCloningKey
            ])
            
            // Network drive detection
            if !(resourceValues.volumeIsLocal ?? true) {
                return .network
            }
            
            // Check if it's likely an SSD (supports APFS cloning)
            if resourceValues.volumeSupportsFileCloning ?? false {
                // Could be NVMe or regular SSD
                // For now, assume internal drives with cloning are NVMe
                if !(resourceValues.volumeIsRemovable ?? true) {
                    return .nvme
                }
                return .ssd
            }
            
            // Removable drives are often HDDs unless proven otherwise
            if resourceValues.volumeIsRemovable ?? false {
                return .hdd
            }
            
            // Default to SSD for internal drives
            return .ssd
            
        } catch {
            return .unknown
        }
    }
    
    enum DriveSpeed: String {
        case nvme = "NVMe"
        case ssd = "SSD"
        case hdd = "HDD"
        case network = "Network"
        case unknown = "Unknown"
        
        var estimatedSpeed: Int { // MB/s
            switch self {
            case .nvme: return 2000
            case .ssd: return 500
            case .hdd: return 150
            case .network: return 100
            case .unknown: return 200
            }
        }
        
        var color: Color {
            switch self {
            case .nvme: return .green
            case .ssd: return .blue
            case .hdd: return .orange
            case .network: return .red
            case .unknown: return .gray
            }
        }
        
        var icon: String {
            switch self {
            case .nvme: return "bolt.fill"
            case .ssd: return "speedometer"
            case .hdd: return "internaldrive"
            case .network: return "network"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

// MARK: - Convenience Extensions
extension MacVolumeAccessModel {
    var hasLastDestinations: Bool {
        !loadLastDestinations().isEmpty
    }

    // Smart worker count based on drive speeds
    func getOptimalWorkerCount(source: DriveSpeed, destinations: [DriveSpeed]) -> Int {
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        
        // If source is slow, limit workers
        if source == .hdd || source == .network {
            return min(2, cpuCount)
        }
        
        // If any destination is slow, moderate workers
        if destinations.contains(where: { $0 == .hdd || $0 == .network }) {
            return min(4, cpuCount)
        }
        
        // All fast drives - use more workers
        return min(8, cpuCount)
    }
    
    // Calculate cascading delays for smart copy
    func calculateCascadingDelays(source: DriveSpeed, destinations: [(URL, DriveSpeed)]) -> [(URL, TimeInterval)] {
        guard destinations.count > 1 else {
            return destinations.map { ($0.0, 0) }
        }
        
        // Sort destinations by speed (fastest first)
        let sorted = destinations.sorted { $0.1.estimatedSpeed > $1.1.estimatedSpeed }
        
        var results: [(URL, TimeInterval)] = []
        var previousSpeed = sorted.first?.1.estimatedSpeed ?? 500
        var cumulativeDelay: TimeInterval = 0
        
        for (url, speed) in sorted {
            // Calculate delay based on speed difference
            if speed.estimatedSpeed < previousSpeed {
                // Slower drive should start later
                let speedRatio = Double(previousSpeed) / Double(speed.estimatedSpeed)
                let additionalDelay = (speedRatio - 1.0) * 0.5 // 50% offset per speed tier
                cumulativeDelay += additionalDelay
            }
            
            results.append((url, cumulativeDelay))
            previousSpeed = speed.estimatedSpeed
        }
        
        return results
    }
}
