// Core/Services/Platform/MacOSFileSystemService.swift
#if os(macOS)
import Foundation
import AppKit
import UserNotifications

final class MacOSFileSystemService: FileSystemService {
    static let shared = MacOSFileSystemService()
    private init() {}
    
    func selectSourceFolder() async -> URL? {
        return await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Source"
            panel.message = "Choose the folder to copy from"
            
            if panel.runModal() == .OK {
                return panel.url
            }
            return nil
        }
    }
    
    func selectDestinationFolders() async -> [URL] {
        return await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "Select Destinations"
            panel.message = "Choose one or more backup destinations"
            
            if panel.runModal() == .OK {
                return panel.urls
            }
            return []
        }
    }
    
    func getVolumeInfo(for url: URL) -> PlatformVolumeInfo? {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey,
                .volumeIdentifierKey
            ])
            
            return PlatformVolumeInfo(
                name: values.volumeName ?? "Unknown",
                totalSpace: Int64(values.volumeTotalCapacity ?? 0),
                availableSpace: Int64(values.volumeAvailableCapacity ?? 0),
                isRemovable: values.volumeIsRemovable ?? false,
                devicePath: (values.volumeIdentifier as? UUID)?.uuidString
            )
        } catch {
            return nil
        }
    }
    
    func getAvailableSpace(at url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            return nil
        }
    }
    
    var volumeUpdates: AsyncStream<PlatformVolumeEvent> {
        // Use existing VolumeMonitorService
        AsyncStream { continuation in
            let monitor = VolumeMonitorService.shared
            
            // Convert existing monitoring to new format
            let cancellable = monitor.$availableCameraCards.sink { volumes in
                // Convert to PlatformVolumeEvents as needed
                // This is a simplified implementation
            }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

final class MacOSSystemIntegrationService: SystemIntegrationService {
    static let shared = MacOSSystemIntegrationService()
    private init() {}
    
    func showAlert(title: String, message: String, style: AlertStyle) async -> AlertResponse {
        return await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            
            switch style {
            case .info:
                alert.alertStyle = .informational
            case .warning:
                alert.alertStyle = .warning
            case .error:
                alert.alertStyle = .critical
            }
            
            alert.addButton(withTitle: "OK")
            
            let response = alert.runModal()
            return response == .alertFirstButtonReturn ? .ok : .cancel
        }
    }
    
    func revealInFileManager(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func openPreferences() {
        // This would trigger the existing preferences window
        NotificationCenter.default.post(name: .showPreferences, object: nil)
    }
    
    func sendNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Show immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
}
#endif