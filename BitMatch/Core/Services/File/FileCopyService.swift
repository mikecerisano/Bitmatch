// Core/Services/File/FileCopyService.swift
import Foundation

/// Handles secure file copying operations with progress tracking
final class FileCopyService {
    
    static func copyAllSafely(
        from src: URL, 
        toRoot dstRoot: URL, 
        workers: Int,
        onProgress: @escaping (String, Int64) -> Void,
        onError: @escaping (String, Error) -> Void
    ) async throws {
        
        // Dev mode simulation
        if DevModeManager.shared.isDevModeEnabled {
            print("🎭 Dev mode: Simulating file copy")
            let fileCount = try await FileCounter.countFiles(at: src)
            
            try await DevModeManager.simulateFakeCopyProgress(
                totalFiles: fileCount,
                onProgress: onProgress,
                onError: onError
            )
            return
        }
        
        let fm = FileManager.default
        
        func updateProgress(file: String, size: Int64) {
            onProgress(file, size)
        }
        
        // Create destination directory structure
        if !fm.fileExists(atPath: dstRoot.path) {
            try fm.createDirectory(at: dstRoot, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Use TaskGroup for concurrent copying
        await withThrowingTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore(count: workers)
            
            // Collect all files first to avoid async enumeration issues
            let filesToCopy = await Task {
                var files: [URL] = []
                if let enumerator = fm.enumerator(
                    at: src,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        files.append(fileURL)
                    }
                }
                return files
            }.value
            
            // Process files concurrently
            for fileURL in filesToCopy {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                        let relativePath = String(fileURL.path.dropFirst(src.path.count + 1))
                        let dstURL = dstRoot.appendingPathComponent(relativePath)
                        
                        if resourceValues.isDirectory == true {
                            // Create directory
                            if !fm.fileExists(atPath: dstURL.path) {
                                try fm.createDirectory(at: dstURL, withIntermediateDirectories: true, attributes: nil)
                            }
                        } else {
                            // Copy file
                            let parentDir = dstURL.deletingLastPathComponent()
                            if !fm.fileExists(atPath: parentDir.path) {
                                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            
                            try await FileCopyService.copyFileSecurely(from: fileURL, to: dstURL)
                            let fileSize = Int64(resourceValues.fileSize ?? 0)
                            updateProgress(file: fileURL.lastPathComponent, size: fileSize)
                        }
                    } catch {
                        onError(fileURL.lastPathComponent, error)
                    }
                }
            }
        }
    }
    
    private static func copyFileSecurely(from source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        
        // Remove existing file if present
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        
        // Copy with metadata preservation
        try fm.copyItem(at: source, to: destination)
        
        // Verify the copy
        let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let destSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        
        guard sourceSize == destSize else {
            try fm.removeItem(at: destination)
            throw FileCopyError.sizeMismatch(expected: sourceSize, actual: destSize)
        }
    }
}

// MARK: - Error Types

enum FileCopyError: LocalizedError {
    case sizeMismatch(expected: Int, actual: Int)
    case copyFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .sizeMismatch(let expected, let actual):
            return "File size mismatch after copy: expected \(expected) bytes, got \(actual) bytes"
        case .copyFailed(let reason):
            return "Copy failed: \(reason)"
        }
    }
}