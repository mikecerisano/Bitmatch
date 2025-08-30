// Core/Services/Platform/IOSFileSystemService.swift
#if os(iOS)
import Foundation
import UIKit
import UniformTypeIdentifiers

final class IOSFileSystemService: FileSystemService {
    static let shared = IOSFileSystemService()
    private init() {}
    
    func selectSourceFolder() async -> URL? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
                picker.allowsMultipleSelection = false
                picker.delegate = DocumentPickerDelegate { urls in
                    continuation.resume(returning: urls.first)
                }
                
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = scene.windows.first?.rootViewController {
                    rootViewController.present(picker, animated: true)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    func selectDestinationFolders() async -> [URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
                picker.allowsMultipleSelection = true
                picker.delegate = DocumentPickerDelegate { urls in
                    continuation.resume(returning: urls)
                }
                
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = scene.windows.first?.rootViewController {
                    rootViewController.present(picker, animated: true)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func getVolumeInfo(for url: URL) -> PlatformVolumeInfo? {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey
            ])
            
            return PlatformVolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                totalSpace: Int64(values.volumeTotalCapacity ?? 0),
                availableSpace: Int64(values.volumeAvailableCapacity ?? 0),
                isRemovable: values.volumeIsRemovable ?? true, // Most external drives on iOS are removable
                devicePath: nil // iOS doesn't expose device paths
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
        // iOS has limited volume monitoring capabilities
        // We'll provide basic monitoring through file system notifications
        AsyncStream { continuation in
            // For now, return empty stream - iOS monitoring is more limited
            continuation.finish()
        }
    }
}

final class IOSSystemIntegrationService: SystemIntegrationService {
    static let shared = IOSSystemIntegrationService()
    private init() {}
    
    func showAlert(title: String, message: String, style: AlertStyle) async -> AlertResponse {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    continuation.resume(returning: .ok)
                })
                
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = scene.windows.first?.rootViewController {
                    rootViewController.present(alert, animated: true)
                } else {
                    continuation.resume(returning: .ok)
                }
            }
        }
    }
    
    func revealInFileManager(_ url: URL) {
        // iOS Files app integration - limited compared to macOS
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    func openPreferences() {
        // iOS apps handle preferences internally or through Settings app
        // For now, this would show an in-app settings view
        print("Opening iOS preferences - would show in-app settings")
    }
    
    func sendNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
}

// Helper class for document picker delegation
private class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: ([URL]) -> Void
    
    init(completion: @escaping ([URL]) -> Void) {
        self.completion = completion
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion([])
    }
}
#endif