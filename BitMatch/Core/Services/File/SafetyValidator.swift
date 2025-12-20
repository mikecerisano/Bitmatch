// Core/Services/File/SafetyValidator.swift
import Foundation

/// Validates file operations for safety before execution
final class SafetyValidator {
    
    // MARK: - Pre-Operation Safety Checks
    
    static func performSafetyChecks(source: URL, destinations: [URL]) async throws {
        // Always perform safety checks in production testing
        
        // Validate source exists and is accessible
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FileOperationError.sourceNotFound(source.path)
        }
        
        // Check source is a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileOperationError.sourceNotDirectory(source.path)
        }
        
        // Check each destination
        for destination in destinations {
            try await validateDestination(destination, source: source)
        }
        
        // Check for sufficient space
        try await validateAvailableSpace(source: source, destinations: destinations)
        
        SharedLogger.info("Safety checks passed for \(destinations.count) destinations", category: .transfer)
    }
    
    private static func validateDestination(_ destination: URL, source: URL) async throws {
        // Create destination directory if it doesn't exist
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Verify it's accessible
        guard fm.isWritableFile(atPath: destination.path) else {
            throw FileOperationError.destinationNotWritable(destination.path)
        }
        
        // Check for dangerous operations
        guard !isUnsafePath(source: source, destination: destination) else {
            throw FileOperationError.unsafeOperation("Cannot copy source to itself or subdirectory")
        }
        
        // Check for symlink loops
        guard !detectSymlinkLoop(at: source) else {
            throw FileOperationError.symlinkLoop(source.path)
        }
        
        // Network drive warning
        if isNetworkVolume(destination) {
            SharedLogger.warning("Network destination detected: \(destination.lastPathComponent) - may be slower", category: .transfer)
        }
    }
    
    private static func validateAvailableSpace(source: URL, destinations: [URL]) async throws {
        let sourceSize = try calculateTotalSize(at: source)
        
        for destination in destinations {
            let availableSpace = getAvailableSpace(at: destination)
            let requiredSpace = sourceSize + 1_000_000_000 // 1GB buffer
            
            guard availableSpace > requiredSpace else {
                let availableGB = Double(availableSpace) / 1_000_000_000
                let requiredGB = Double(requiredSpace) / 1_000_000_000
                throw FileOperationError.insufficientSpace(
                    destination.path,
                    available: availableGB,
                    required: requiredGB
                )
            }
        }
    }
    
    // MARK: - Network Drive Detection
    
    static func isNetworkVolume(_ url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRemovableKey])
            return !(resourceValues.volumeIsLocal ?? true)
        } catch {
            return false
        }
    }
    
    // MARK: - Symlink Loop Detection
    
    private static func detectSymlinkLoop(at url: URL, visited: Set<URL> = []) -> Bool {
        guard visited.count < 100 else { return true } // Prevent infinite recursion
        
        var newVisited = visited
        newVisited.insert(url)
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                let resolved = try URL(resolvingAliasFileAt: url)
                return newVisited.contains(resolved) || detectSymlinkLoop(at: resolved, visited: newVisited)
            }
        } catch {
            return false
        }
        
        return false
    }
    
    // MARK: - Path Safety
    
    private static func isUnsafePath(source: URL, destination: URL) -> Bool {
        let sourcePath = source.standardized.path
        let destPath = destination.standardized.path
        
        // Don't copy to self
        if sourcePath == destPath {
            return true
        }
        
        // Don't copy to subdirectory of itself
        if destPath.hasPrefix(sourcePath + "/") {
            return true
        }
        
        return false
    }
    
    // MARK: - Utility Functions
    
    private static func calculateTotalSize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory != true {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
        }
        
        return totalSize
    }
    
    private static func getAvailableSpace(at url: URL) -> Int64 {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
}

// MARK: - Error Types

enum FileOperationError: LocalizedError {
    case sourceNotFound(String)
    case sourceNotDirectory(String)
    case destinationNotWritable(String)
    case unsafeOperation(String)
    case symlinkLoop(String)
    case insufficientSpace(String, available: Double, required: Double)
    
    var errorDescription: String? {
        switch self {
        case .sourceNotFound(_):
            return "Source folder not found"
        case .sourceNotDirectory(_):
            return "Source is not a directory"
        case .destinationNotWritable(_):
            return "Cannot write to destination"
        case .unsafeOperation(_):
            return "Unsafe operation"
        case .symlinkLoop(_):
            return "Symlink loop detected"
        case .insufficientSpace(_, let available, let required):
            return "Insufficient space: \(String(format: "%.1f", available))GB available, \(String(format: "%.1f", required))GB required"
        }
    }
}
