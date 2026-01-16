// MacOSPlatformManager.swift - macOS platform coordination
import Foundation
#if os(macOS)
import AppKit

@MainActor
class MacOSPlatformManager: PlatformManager {
    static let shared = MacOSPlatformManager()
    
    // MARK: - Service Instances
    nonisolated var fileSystem: FileSystemService {
        MacOSFileSystemService.shared
    }
    
    nonisolated var checksum: ChecksumService {
        SharedChecksumService.shared
    }
    
    // Thread-safe lazy initialization via static let
    private static let _sharedFileOperations = SharedFileOperationsService(
        fileSystem: MacOSFileSystemService.shared,
        checksum: SharedChecksumService.shared
    )
    private static let _sharedCameraDetection = SharedCameraDetectionService()

    nonisolated var fileOperations: FileOperationsService {
        Self._sharedFileOperations
    }

    nonisolated var cameraDetection: CameraDetectionService {
        Self._sharedCameraDetection
    }

    nonisolated var supportsDragAndDrop: Bool {
        return true // macOS supports drag and drop
    }

    private init() {
        // Services are now initialized via static properties for thread safety
    }
    
    // MARK: - Platform-specific UI Methods
    
    @MainActor
    func presentAlert(title: String, message: String) async {
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            
            alert.runModal()
            continuation.resume()
        }
    }
    
    func presentError(_ error: Error) async {
        await presentAlert(title: "Error", message: error.localizedDescription)
    }
    
    func openURL(_ url: URL) async -> Bool {
        return await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - macOS-specific Utilities
    
    func requestDocumentAccess() async -> Bool {
        // macOS document access setup if needed
        return true
    }
    
    func checkStoragePermissions() async -> Bool {
        // Check macOS storage permissions
        return true
    }
    
    // MARK: - Background Tasks
    
    func beginBackgroundTask(name: String?, expirationHandler: (() -> Void)?) -> Int {
        // macOS doesn't use UIKit background tasks in the same way; returning a dummy ID.
        // Use ProcessInfo.processInfo.beginActivity(options:reason:) if preventing sleep is needed.
        return 0
    }
    
    func endBackgroundTask(_ id: Int) {
        // No-op
    }
}
#endif
