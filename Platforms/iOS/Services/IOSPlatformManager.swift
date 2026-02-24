// IOSPlatformManager.swift - iOS platform coordination
import Foundation
import UIKit

class IOSPlatformManager: PlatformManager {
    static let shared = IOSPlatformManager()
    
    // MARK: - Service Instances
    var fileSystem: FileSystemService {
        IOSFileSystemService.shared
    }
    
    var checksum: ChecksumService {
        SharedChecksumService.shared
    }
    
    var fileOperations: FileOperationsService {
        _fileOperations
    }
    
    var cameraDetection: CameraDetectionService {
        _cameraDetection
    }
    
    var supportsDragAndDrop: Bool {
        return false // iOS/iPadOS has limited drag and drop support
    }
    
    private let _fileOperations: any FileOperationsService
    private let _cameraDetection: any CameraDetectionService
    
    private init() {
        self._fileOperations = SharedFileOperationsService(
            fileSystem: IOSFileSystemService.shared,
            checksum: SharedChecksumService.shared
        )
        self._cameraDetection = SharedCameraDetectionService()
    }
    
    // MARK: - Platform-specific UI Methods
    
    func presentAlert(title: String, message: String) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
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
    }
    
    func presentError(_ error: Error) async {
        await presentAlert(title: "Error", message: error.localizedDescription)
    }
    
    func openURL(_ url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
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
        final class TaskIDBox { var id: UIBackgroundTaskIdentifier = .invalid }
        let box = TaskIDBox()

        let register: () -> Void = {
            box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
                expirationHandler?()
                let current = box.id
                if current != .invalid {
                    UIApplication.shared.endBackgroundTask(current)
                    box.id = .invalid
                }
            }
        }

        if Thread.isMainThread {
            register()
        } else {
            DispatchQueue.main.sync(execute: register)
        }

        return box.id.rawValue
    }
    
    func endBackgroundTask(_ id: Int) {
        let endTask: () -> Void = {
            let identifier = UIBackgroundTaskIdentifier(rawValue: id)
            if identifier != .invalid {
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }

        if Thread.isMainThread {
            endTask()
        } else {
            DispatchQueue.main.sync(execute: endTask)
        }
    }
}
