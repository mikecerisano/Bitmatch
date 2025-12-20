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
    
    func selectLeftFolder() async -> URL? {
        return await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Left Folder"
            panel.message = "Choose the first folder to compare"
            
            if panel.runModal() == .OK {
                return panel.url
            }
            return nil
        }
    }
    
    func selectRightFolder() async -> URL? {
        return await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Right Folder"
            panel.message = "Choose the second folder to compare"
            
            if panel.runModal() == .OK {
                return panel.url
            }
            return nil
        }
    }
    
    func validateFileAccess(url: URL) async -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    func startAccessing(url: URL) -> Bool {
        return true
    }

    func stopAccessing(url: URL) {}
    
    func getFileList(from folderURL: URL) async throws -> [URL] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let directoryEnumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        )
        
        var fileURLs: [URL] = []
        guard let directoryEnumerator = directoryEnumerator else { return fileURLs }
        let anyEnum: NSEnumerator = directoryEnumerator
        while let fileURL = anyEnum.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isRegularFile == true {
                fileURLs.append(fileURL)
            }
        }
        return fileURLs
    }
    
    func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
    
    nonisolated func getFileSize(for url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    nonisolated func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    nonisolated func freeSpace(at url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            SharedLogger.error("Error checking free space: \(error)", category: .transfer)
            return 0
        }
    }
}

#endif
