// Core/Services/File/FileCounter.swift
import Foundation

/// Handles file counting and enumeration operations
final class FileCounter {
    
    static func countFiles(at url: URL) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let count = try countFilesSync(at: url)
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func countFilesSync(at url: URL) throws -> Int {
        let fm = FileManager.default
        var count = 0
        
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory != true {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    /// Count files with retry logic for transient errors
    static func countFilesWithRetry(at url: URL, maxRetries: Int = 3) async throws -> Int {
        return try await retryWithBackoff(maxRetries: maxRetries) {
            try await countFiles(at: url)
        }
    }
    
    // MARK: - Retry Logic
    
    static func retryWithBackoff<T>(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 0.5,
        backoffMultiplier: Double = 2.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        
        var delay = initialDelay
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on final attempt or non-transient errors
                if attempt == maxRetries - 1 || !isTransientError(error) {
                    throw error
                }
                
                print("⚠️ Attempt \\(attempt + 1) failed, retrying in \\(delay)s: \\(error.localizedDescription)")
                
                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= backoffMultiplier
            }
        }
        
        throw lastError ?? NSError(domain: "FileCounter", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Max retries exceeded"
        ])
    }
    
    private static func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Network/filesystem transient errors
        switch nsError.code {
        case NSFileReadNoSuchFileError,
             NSFileReadNoPermissionError,
             NSFileReadCorruptFileError:
            return false // Permanent errors
            
        case NSFileReadUnknownError,
             NSFileReadTooLargeError,
             NSFileReadUnknownStringEncodingError:
            return true // Potentially transient
            
        default:
            // Check for system-level errors that might be transient
            if nsError.domain == NSPOSIXErrorDomain {
                switch nsError.code {
                case Int(EAGAIN), Int(EBUSY), Int(ETIMEDOUT), Int(ENOENT):
                    return true
                default:
                    return false
                }
            }
            
            return false
        }
    }
}