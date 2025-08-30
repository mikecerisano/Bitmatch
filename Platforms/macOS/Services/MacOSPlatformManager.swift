// MacOSPlatformManager.swift - macOS platform coordination
import Foundation
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
    
    nonisolated var fileOperations: FileOperationsService {
        _fileOperations
    }
    
    nonisolated var cameraDetection: CameraDetectionService {
        _cameraDetection
    }
    
    private let _fileOperations: any FileOperationsService
    private let _cameraDetection: any CameraDetectionService
    
    private init() {
        self._fileOperations = SharedFileOperationsService(
            fileSystem: MacOSFileSystemService.shared,
            checksum: SharedChecksumService.shared
        )
        self._cameraDetection = SharedCameraDetectionService()
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
}