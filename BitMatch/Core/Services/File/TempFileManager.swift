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
}