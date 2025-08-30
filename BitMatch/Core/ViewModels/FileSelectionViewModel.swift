// Core/ViewModels/FileSelectionViewModel.swift
import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

@MainActor
final class FileSelectionViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var leftURL: URL? {
        didSet {
            handleURLChange(leftURL, for: .left)
        }
    }
    
    @Published var rightURL: URL? {
        didSet {
            handleURLChange(rightURL, for: .right)
        }
    }
    
    @Published var sourceURL: URL? {
        didSet {
            handleURLChange(sourceURL, for: .source)
        }
    }
    
    @Published var destinationURLs: [URL] = [] {
        didSet {
            // Auto-save destinations when they change
            if !destinationURLs.isEmpty {
                saveLastDestinations()
            }
        }
    }
    @Published var recentFolders: [URL] = []
    
    // Folder Info
    @Published var leftFolderInfo: FolderInfo?
    @Published var rightFolderInfo: FolderInfo?
    @Published var sourceFolderInfo: FolderInfo?
    
    // Loading States
    @Published var isFetchingLeftInfo = false
    @Published var isFetchingRightInfo = false
    @Published var isFetchingSourceInfo = false
    
    // Source Protection
    @Published var sourceIsWriteProtected = false
    
    // Auto-detected volumes
    @Published var detectedCameraCards: [VolumeMonitorService.DetectedVolume] = []
    @Published var detectedBackupDrives: [VolumeMonitorService.DetectedVolume] = []
    
    // MARK: - Private Properties
    private enum InfoTarget { case left, right, source }
    private let lastDestinationsKey = "lastUsedDestinations"
    private let maxRememberedDestinations = 5
    private let recentFoldersListKey = "recentFoldersList"
    var volumeMonitor = VolumeMonitorService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadRecentFolders()
        setupVolumeMonitoring()
        loadSavedBookmarks()
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
                print("📤 Selected source volume was removed: \(sourceURL.lastPathComponent)")
                self.sourceURL = nil
            }
        }
        
        // Auto-populate first detected camera card as source if none selected
        if sourceURL == nil, let firstCard = cards.first {
            sourceURL = firstCard.url
            print("📷 Auto-selected camera card: \(firstCard.displayName)")
        }
    }
    
    private func handleBackupDrivesUpdate(_ drives: [VolumeMonitorService.DetectedVolume]) {
        // Check if any current destinations are no longer available
        let driveURLs = Set(drives.map { $0.url.path })
        let removedDestinations = destinationURLs.filter { destination in
            !driveURLs.contains(destination.path) && !FileManager.default.fileExists(atPath: destination.path)
        }
        
        for removed in removedDestinations {
            print("📤 Auto-removing unavailable destination: \(removed.lastPathComponent)")
            removeDestination(removed)
        }
        
        // Auto-add new backup drives as destinations
        for drive in drives {
            if !destinationURLs.contains(drive.url) {
                addDestination(drive.url)
                print("💾 Auto-added backup drive: \(drive.displayName)")
            }
        }
    }
    
    // MARK: - Public Methods
    func addDestination(_ url: URL) {
        guard !destinationURLs.contains(url) else { return }
        destinationURLs.append(url)
        saveRecentFolder(url, key: "recentDestination")
    }
    
    func removeDestination(_ url: URL) {
        destinationURLs.removeAll { $0 == url }
    }
    
    func clearAllSelections() {
        leftURL = nil
        rightURL = nil
        sourceURL = nil
        destinationURLs.removeAll()
    }
    
    func removeAutoDetectedCameraCard(_ volume: VolumeMonitorService.DetectedVolume) {
        // If this was our auto-selected source, clear it
        if sourceURL == volume.url {
            sourceURL = nil
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
        print("🧪 Testing volume detection manually...")
        let testVolumes = [
            URL(fileURLWithPath: "/Volumes/Untitled"),
            URL(fileURLWithPath: "/Volumes/T9"),
            URL(fileURLWithPath: "/Volumes/T9/FUJI XT30")
        ]
        
        for url in testVolumes {
            if FileManager.default.fileExists(atPath: url.path) {
                print("🧪 Testing volume: \(url.path)")
                
                // Test camera detection specifically
                let cameraType = CameraDetectionOrchestrator.shared.detectCamera(at: url)
                print("🎥 Camera detection result: \(cameraType ?? "None")")
                
                // Test specific Fuji detection
                if let fujiResult = FujiDetectionService.shared.detectFujiCamera(at: url) {
                    print("📷 Fuji detection: \(fujiResult)")
                } else {
                    print("📷 No Fuji files found")
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
            
            print("🔐 Granted access to: \(selectedURL.path)")
            
            // Store security-scoped bookmark for the selected directory
            do {
                #if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
                #else
                let bookmarkOptions: URL.BookmarkCreationOptions = []
                #endif
                
                let bookmarkData = try selectedURL.bookmarkData(
                    options: bookmarkOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                let key = "volumesDirectoryBookmark"
                UserDefaults.standard.set(bookmarkData, forKey: key)
                UserDefaults.standard.set(selectedURL.path, forKey: "volumesDirectoryPath")
                
                print("🔖 Saved volumes directory bookmark for: \(selectedURL.path)")
                
                // Start accessing the security-scoped resource immediately
                if selectedURL.startAccessingSecurityScopedResource() {
                    print("🔓 Started accessing volumes directory: \(selectedURL.path)")
                    
                    // Trigger a fresh volume scan
                    self?.volumeMonitor.refreshVolumes()
                }
                
            } catch {
                print("❌ Failed to create bookmark for \(selectedURL.path): \(error)")
            }
        }
        #else
        // iOS doesn't have NSOpenPanel - volume access is handled differently
        print("⚠️ Volume access request not available on iOS")
        #endif
    }
    
    func loadSavedBookmarks() {
        let defaults = UserDefaults.standard
        
        // Check for the volumes directory bookmark first
        if let bookmarkData = defaults.data(forKey: "volumesDirectoryBookmark") {
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
                    print("📚 Restored volumes directory bookmark: \(url.path)")
                    
                    // Start accessing the security-scoped resource
                    if url.startAccessingSecurityScopedResource() {
                        print("🔓 Started accessing volumes directory: \(url.path)")
                        
                        // Trigger volume scan - this should now work for all volumes
                        volumeMonitor.refreshVolumes()
                        
                        // Don't stop accessing - we want persistent access
                        return // We have volumes access, no need to check individual bookmarks
                    }
                } else {
                    print("🗑️ Removing stale volumes directory bookmark")
                    defaults.removeObject(forKey: "volumesDirectoryBookmark")
                    defaults.removeObject(forKey: "volumesDirectoryPath")
                }
            } catch {
                print("❌ Failed to resolve volumes directory bookmark: \(error)")
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
                        print("📚 Restored individual bookmark for: \(url.lastPathComponent)")
                        
                        // Start accessing the security-scoped resource
                        if url.startAccessingSecurityScopedResource() {
                            print("🔓 Started accessing: \(url.path)")
                            
                            // Analyze the volume
                            volumeMonitor.forceAnalyzeVolume(at: url)
                        }
                    } else {
                        print("🗑️ Removing stale bookmark for: \(key)")
                        defaults.removeObject(forKey: key)
                    }
                } catch {
                    print("❌ Failed to resolve bookmark \(key): \(error)")
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }
    
    var hasVolumeAccess: Bool {
        return UserDefaults.standard.data(forKey: "volumesDirectoryBookmark") != nil
    }
    
    // MARK: - Smart Defaults Methods
    func saveLastDestinations() {
        let paths = destinationURLs.prefix(maxRememberedDestinations).map { $0.path }
        UserDefaults.standard.set(paths, forKey: lastDestinationsKey)
    }
    
    func loadLastDestinations() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: lastDestinationsKey) else {
            return []
        }
        
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            // Only return if the path still exists
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }
    
    func restoreLastDestinations() {
        let lastDests = loadLastDestinations()
        for dest in lastDests {
            if !destinationURLs.contains(dest) {
                destinationURLs.append(dest)
            }
        }
    }
    
    // MARK: - Validation
    var canCompare: Bool {
        leftURL != nil && rightURL != nil
    }
    
    var canCopyAndVerify: Bool {
        sourceURL != nil && !destinationURLs.isEmpty
    }
    
    func validateDestinations(for source: URL) -> [URL] {
        return destinationURLs.filter { destination in
            // Check if destination is safe (not same as source, not ancestor)
            destination.standardizedFileURL != source.standardizedFileURL &&
            !source.isAncestor(of: destination)
        }
    }
    
    // MARK: - Private Methods
    private func handleURLChange(_ url: URL?, for target: InfoTarget) {
        switch target {
        case .left:
            saveRecentFolder(url, key: "recentLeft")
            fetchInfo(for: .left)
        case .right:
            saveRecentFolder(url, key: "recentRight")
            fetchInfo(for: .right)
        case .source:
            saveRecentFolder(url, key: "recentSource")
            fetchInfo(for: .source)
        }
    }
    
    private func fetchInfo(for target: InfoTarget) {
        let url: URL?
        
        switch target {
        case .left:
            isFetchingLeftInfo = leftURL != nil
            leftFolderInfo = nil
            url = leftURL
        case .right:
            isFetchingRightInfo = rightURL != nil
            rightFolderInfo = nil
            url = rightURL
        case .source:
            isFetchingSourceInfo = sourceURL != nil
            sourceFolderInfo = nil
            url = sourceURL
        }
        
        guard let urlToFetch = url else { return }
        
        Task {
            let info = await FolderInfoService.getFolderInfo(for: urlToFetch)
            
            switch target {
            case .left:
                leftFolderInfo = info
                isFetchingLeftInfo = false
            case .right:
                rightFolderInfo = info
                isFetchingRightInfo = false
            case .source:
                sourceFolderInfo = info
                isFetchingSourceInfo = false
                if let url = sourceURL {
                    sourceIsWriteProtected = FolderInfoService.checkWriteProtection(url: url)
                }
            }
        }
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
extension FileSelectionViewModel {
    var hasSourceAndDestinations: Bool {
        sourceURL != nil && !destinationURLs.isEmpty
    }
    
    var hasLeftAndRight: Bool {
        leftURL != nil && rightURL != nil
    }
    
    var hasLastDestinations: Bool {
        !loadLastDestinations().isEmpty
    }
    
    func getWorkerCount() -> Int {
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        let isSourceSSD = sourceFolderInfo?.isInternalDrive ?? false
        let baseWorkers = isSourceSSD ? cpuCount : max(2, cpuCount / 2)
        return max(2, min(8, baseWorkers))
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
