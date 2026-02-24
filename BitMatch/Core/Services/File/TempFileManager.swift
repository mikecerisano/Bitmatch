// Core/Services/File/TempFileManager.swift
import Foundation

/// Manages temporary files and cleanup operations
final class TempFileManager {
    
    // MARK: - Track temp files for cleanup
    private static var activeTempFiles = Set<URL>()
    private static let tempFilesLock = NSLock()
    
    static func addTempFile(_ url: URL) {
        tempFilesLock.lock()
        activeTempFiles.insert(url)
        tempFilesLock.unlock()
    }
    
    static func removeTempFile(_ url: URL) {
        tempFilesLock.lock()
        activeTempFiles.remove(url)
        tempFilesLock.unlock()
    }
    
    static func cleanupAllTempFiles() {
        tempFilesLock.lock()
        let files = activeTempFiles
        tempFilesLock.unlock()
        
        let fm = FileManager.default
        for file in files {
            try? fm.removeItem(at: file)
        }
        
        tempFilesLock.lock()
        activeTempFiles.removeAll()
        tempFilesLock.unlock()
    }
    
    /// Get active temp files count for debugging
    static var activeTempFileCount: Int {
        tempFilesLock.lock()
        defer { tempFilesLock.unlock() }
        return activeTempFiles.count
    }

    /// Security 12: clean up orphaned .bitmatch.tmp.* files from previous crashed sessions
    static func cleanupOrphanedTempFiles(in directory: URL? = nil) {
        let fm = FileManager.default
        let searchDirs: [URL]
        if let dir = directory {
            searchDirs = [dir]
        } else {
            searchDirs = [fm.temporaryDirectory]
        }
        for dir in searchDirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsSubdirectoryDescendants]
            ) else { continue }
            let staleThreshold = Date().addingTimeInterval(-3600) // 1 hour old
            for case let fileURL as URL in enumerator {
                let name = fileURL.lastPathComponent
                guard name.hasPrefix(".bitmatch.tmp.") else { continue }
                if let created = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                   created < staleThreshold {
                    try? fm.removeItem(at: fileURL)
                }
            }
        }
    }
}