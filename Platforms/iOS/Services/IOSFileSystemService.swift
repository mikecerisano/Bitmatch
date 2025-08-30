// IOSFileSystemService.swift - iOS-specific file system implementation
import Foundation
import UIKit
import UniformTypeIdentifiers

class IOSFileSystemService: NSObject, FileSystemService {
    static let shared = IOSFileSystemService()
    
    private override init() {
        super.init()
    }
    
    // MARK: - FileSystemService Protocol Implementation
    
    @MainActor
    func selectSourceFolder() async -> URL? {
        return await selectFolder(allowMultiple: false).first
    }
    
    @MainActor
    func selectDestinationFolders() async -> [URL] {
        return await selectFolder(allowMultiple: true)
    }
    
    @MainActor
    func selectLeftFolder() async -> URL? {
        return await selectFolder(allowMultiple: false).first
    }
    
    @MainActor
    func selectRightFolder() async -> URL? {
        return await selectFolder(allowMultiple: false).first
    }
    
    func validateFileAccess(url: URL) async -> Bool {
        return url.startAccessingSecurityScopedResource()
    }
    
    func getFileList(from folderURL: URL) async throws -> [URL] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )
        
        var fileURLs: [URL] = []
        
        while let url = enumerator?.nextObject() as? URL {
            let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isRegularFile == true {
                fileURLs.append(url)
            }
        }
        
        return fileURLs
    }
    
    func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try createDirectory(at: destinationURL.deletingLastPathComponent())
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
    
    nonisolated func getFileSize(for url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    nonisolated func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Private iOS-specific Implementation
    
    @MainActor
    private func selectFolder(allowMultiple: Bool) async -> [URL] {
        return await withCheckedContinuation { continuation in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = allowMultiple
            picker.delegate = DocumentPickerDelegate { urls in
                continuation.resume(returning: urls)
            }
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(picker, animated: true)
            } else {
                continuation.resume(returning: [])
            }
        }
    }
}

// MARK: - Document Picker Delegate
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