// MacOSPlatformManager.swift - macOS platform coordination
import Foundation
#if os(macOS)
import AppKit

class MacOSPlatformManager: PlatformManager {
    static let shared = MacOSPlatformManager()
    
    // MARK: - Service Instances
    var fileSystem: FileSystemService {
        MacOSFileSystemService.shared
    }
    
    var checksum: ChecksumService {
        SharedChecksumService.shared
    }
    
    // Thread-safe lazy initialization via static let
    private static let _sharedFileOperations = SharedFileOperationsService(
        fileSystem: MacOSFileSystemService.shared,
        checksum: SharedChecksumService.shared
    )
    private static let _sharedCameraDetection = SharedCameraDetectionService()

    var fileOperations: FileOperationsService {
        Self._sharedFileOperations
    }

    var cameraDetection: CameraDetectionService {
        Self._sharedCameraDetection
    }

    var supportsDragAndDrop: Bool {
        return true // macOS supports drag and drop
    }

    private init() {
        // Services are now initialized via static properties for thread safety
    }
    
    // MARK: - Platform-specific UI Methods
    
    func presentAlert(title: String, message: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.runModal()
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
    
}
#endif
