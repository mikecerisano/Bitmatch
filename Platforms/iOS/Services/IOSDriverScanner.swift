// IOSDriverScanner.swift - iOS-specific drive scanning and report discovery
import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
class IOSDriverScanner: NSObject {
    private static var currentDrivePickerDelegate: DrivePickerDelegate?
    
    // MARK: - Drive Selection and Scanning
    
    /// Present drive/folder selection UI and scan for BitMatch reports
    static func selectDriveAndScan() async -> [TransferCard] {
        SharedLogger.info("Starting iOS drive selection for Master Report scanning...")

        // Present folder picker for drive selection
        guard let selectedURL = await presentDriveSelector() else {
            SharedLogger.info("Drive selection cancelled")
            return []
        }

        SharedLogger.info("Selected drive: \(selectedURL.path)")
        
        // Ensure we have access to the selected location
        guard selectedURL.startAccessingSecurityScopedResource() else {
            SharedLogger.error("Failed to access security scoped resource")
            return []
        }
        
        defer {
            selectedURL.stopAccessingSecurityScopedResource()
        }
        
        // Scan the selected drive for BitMatch reports
        return await scanForBitMatchReports(at: selectedURL)
    }
    
    /// Get available drives/volumes for selection
    static func getAvailableVolumes() -> [VolumeInfo] {
        var volumes: [VolumeInfo] = []
        
        // On iOS, we mainly work with app sandbox and external storage
        let fileManager = FileManager.default
        
        // Document directory (internal)
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            volumes.append(VolumeInfo(
                name: "Documents",
                path: documentsURL.path,
                url: documentsURL,
                isExternal: false,
                isRemovable: false,
                volumeType: .`internal`
            ))
        }
        
        // Try to detect external storage through mounted volumes
        // Note: On iOS, access to external drives is limited to document picker
        let mountedVolumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey
        ], options: [])
        
        for volumeURL in mountedVolumes ?? [] {
            do {
                let resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeIsRemovableKey,
                    .volumeIsInternalKey
                ])
                
                let name = resourceValues.volumeName ?? volumeURL.lastPathComponent
                let isRemovable = resourceValues.volumeIsRemovable ?? false
                let isInternal = resourceValues.volumeIsInternal ?? true
                
                // Only add external/removable volumes for scanning
                if !isInternal || isRemovable {
                    volumes.append(VolumeInfo(
                        name: name,
                        path: volumeURL.path,
                        url: volumeURL,
                        isExternal: !isInternal,
                        isRemovable: isRemovable,
                        volumeType: isRemovable ? .removable : .external
                    ))
                }
            } catch {
                SharedLogger.error("Error reading volume info for \(volumeURL): \(error)")
            }
        }

        SharedLogger.info("Found \(volumes.count) available volumes")
        return volumes
    }
    
    // MARK: - BitMatch Report Scanning
    
    /// Scan a drive/folder for BitMatch reports. The rules (filenames, size
    /// limit, date window, what "verified" means) are shared with the Mac in
    /// `ReportScanner`, which also starts security-scoped access for the scan.
    static func scanForBitMatchReports(at rootURL: URL, day: Date = Date()) async -> [TransferCard] {
        await ReportScanner.scan(at: rootURL, day: day)
    }
    
    // MARK: - Private Helper Methods
    
    private static func presentDriveSelector() async -> URL? {
        return await withCheckedContinuation { continuation in
            let picker = makeDrivePicker { url in
                continuation.resume(returning: url)
            }
            
            // Present the picker
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                
                // Configure for iPad if needed
                if UIDevice.current.userInterfaceIdiom == .pad {
                    picker.modalPresentationStyle = .formSheet
                }
                
                rootViewController.present(picker, animated: true)
            } else {
                currentDrivePickerDelegate = nil
                continuation.resume(returning: nil)
            }
        }
    }

    private static func makeDrivePicker(completion: @escaping (URL?) -> Void) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        let delegate = DrivePickerDelegate { url in
            currentDrivePickerDelegate = nil
            completion(url)
        }
        currentDrivePickerDelegate = delegate
        picker.delegate = delegate
        return picker
    }

    #if DEBUG
    static var hasRetainedDrivePickerDelegateForTesting: Bool {
        currentDrivePickerDelegate != nil
    }

    static func clearRetainedDrivePickerDelegateForTesting() {
        currentDrivePickerDelegate = nil
    }

    static func makeDrivePickerForTesting(completion: @escaping (URL?) -> Void) -> UIDocumentPickerViewController {
        makeDrivePicker(completion: completion)
    }
    #endif
}

// MARK: - Supporting Types

struct VolumeInfo {
    let name: String
    let path: String
    let url: URL
    let isExternal: Bool
    let isRemovable: Bool
    let volumeType: VolumeType
    
    enum VolumeType {
        case `internal`
        case external
        case removable
        case network
    }
}

// MARK: - Document Picker Delegate for Drive Selection

private class DrivePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void
    
    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
