// Core/Services/Platform/FileSystemService.swift
import Foundation

/// Platform abstraction for file system operations
protocol FileSystemService {
    /// Select a source folder for operations
    func selectSourceFolder() async -> URL?
    
    /// Select multiple destination folders
    func selectDestinationFolders() async -> [URL]
    
    /// Get volume information for a URL
    func getVolumeInfo(for url: URL) -> PlatformVolumeInfo?
    
    /// Check available space at URL
    func getAvailableSpace(at url: URL) -> Int64?
    
    /// Monitor for volume/drive changes
    var volumeUpdates: AsyncStream<PlatformVolumeEvent> { get }
}

/// Cross-platform volume information
struct PlatformVolumeInfo {
    let name: String
    let totalSpace: Int64
    let availableSpace: Int64
    let isRemovable: Bool
    let devicePath: String?
}

/// Volume change events
enum PlatformVolumeEvent {
    case mounted(PlatformVolumeInfo)
    case unmounted(PlatformVolumeInfo)
    case updated(PlatformVolumeInfo)
}

/// Platform abstraction for system integration
protocol SystemIntegrationService {
    /// Show an alert to the user
    func showAlert(title: String, message: String, style: AlertStyle) async -> AlertResponse
    
    /// Reveal file in system file manager
    func revealInFileManager(_ url: URL)
    
    /// Open system preferences/settings
    func openPreferences()
    
    /// Send a system notification
    func sendNotification(title: String, message: String)
}

enum AlertStyle {
    case info
    case warning
    case error
}

enum AlertResponse {
    case ok
    case cancel
    case primary
    case secondary
}