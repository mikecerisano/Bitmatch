// IOSPlatformManager.swift - iOS platform coordination
import Foundation
import UIKit

@MainActor
class IOSPlatformManager: PlatformManager {
    static let shared = IOSPlatformManager()
    
    // MARK: - Service Instances
    nonisolated var fileSystem: FileSystemService {
        IOSFileSystemService.shared
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
    
    nonisolated var supportsDragAndDrop: Bool {
        return false // iOS/iPadOS has limited drag and drop support
    }
    
    private nonisolated let _fileOperations: any FileOperationsService
    private nonisolated let _cameraDetection: any CameraDetectionService
    
    private init() {
        self._fileOperations = SharedFileOperationsService(
            fileSystem: IOSFileSystemService.shared,
            checksum: SharedChecksumService.shared
        )
        self._cameraDetection = SharedCameraDetectionService()
    }
    
    // MARK: - Platform-specific UI Methods
    
    @MainActor
    func presentAlert(title: String, message: String) async {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            } else {
                continuation.resume()
            }
        }
    }
    
    func presentError(_ error: Error) async {
        await presentAlert(title: "Error", message: error.localizedDescription)
    }
    
    func openURL(_ url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url) { success in
                        continuation.resume(returning: success)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - iOS-specific Utilities
    
    func requestDocumentAccess() async -> Bool {
        // iOS-specific document access setup if needed
        return true
    }
    
    func checkStoragePermissions() async -> Bool {
        // Check iOS storage permissions
        return true
    }
    
    // MARK: - Background Tasks
    
    func beginBackgroundTask(name: String?, expirationHandler: (() -> Void)?) -> Int {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            expirationHandler?()
            UIApplication.shared.endBackgroundTask(identifier)
        }
        return identifier.rawValue
    }
    
    func endBackgroundTask(_ id: Int) {
        let identifier = UIBackgroundTaskIdentifier(rawValue: id)
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }
}