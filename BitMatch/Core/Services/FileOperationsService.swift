// Core/Services/FileOperationsService.swift - Refactored
import Foundation

/// Coordinates file operations between specialized services
/// Refactored from monolithic service into focused components
final class FileOperationsService {
    
    // MARK: - Public API (maintains compatibility)
    
    static func performSafetyChecks(source: URL, destinations: [URL]) async throws {
        // Skip safety checks in dev mode since we're using fake URLs
        if DevModeManager.shared.isDevModeEnabled {
            print("🎭 Skipping safety checks in dev mode")
            return
        }
        try await SafetyValidator.performSafetyChecks(source: source, destinations: destinations)
    }
    
    static func countFiles(at url: URL) async throws -> Int {
        // Return fake count in dev mode
        if DevModeManager.shared.isDevModeEnabled {
            let fakeCount = Int.random(in: 150...450)
            print("🎭 Returning fake file count: \(fakeCount)")
            return fakeCount
        }
        return try await FileCounter.countFiles(at: url)
    }
    
    static func copyAllSafely(
        from src: URL,
        toRoot dstRoot: URL,
        workers: Int,
        onProgress: @escaping (String, Int64) -> Void,
        onError: @escaping (String, Error) -> Void
    ) async throws {
        try await FileCopyService.copyAllSafely(
            from: src,
            toRoot: dstRoot,
            workers: workers,
            onProgress: onProgress,
            onError: onError
        )
    }
    
    static func compareFile(
        leftURL: URL,
        rightURL: URL,
        relativePath: String,
        verificationMode: VerificationMode
    ) async -> ResultRow {
        
        switch verificationMode {
        case .quick:
            // Size-only comparison (fastest)
            return await compareBySizeOnly(leftURL: leftURL, rightURL: rightURL, relativePath: relativePath)
            
        case .standard:
            // Byte-by-byte comparison (recommended)
            return await ChecksumService.compareFileByteByByte(
                leftURL: leftURL,
                rightURL: rightURL,
                relativePath: relativePath
            )
            
        case .thorough:
            // SHA-256 checksum comparison (secure)
            return await ChecksumService.compareFile(
                leftURL: leftURL,
                rightURL: rightURL,
                relativePath: relativePath,
                algorithm: .sha256
            )
            
        case .paranoid:
            // Both checksum AND byte-by-byte (production standard)
            let checksumResult = await ChecksumService.compareFile(
                leftURL: leftURL,
                rightURL: rightURL,
                relativePath: relativePath,
                algorithm: .sha256
            )
            
            // If checksum passes, do byte-by-byte verification
            if checksumResult.status == .match {
                return await ChecksumService.compareFileByteByByte(
                    leftURL: leftURL,
                    rightURL: rightURL,
                    relativePath: relativePath
                )
            } else {
                return checksumResult
            }
        }
    }
    
    static func computeChecksum(for url: URL, algorithm: ChecksumAlgorithm) throws -> String {
        try ChecksumService.computeChecksum(for: url, algorithm: algorithm)
    }
    
    static func computeChecksumWithCache(for url: URL, algorithm: ChecksumAlgorithm) async throws -> String {
        try await ChecksumService.computeChecksumWithCache(for: url, algorithm: algorithm)
    }
    
    static func computeChecksums(for urls: [URL], algorithm: ChecksumAlgorithm) async throws -> [(URL, String)] {
        try await ChecksumService.computeChecksums(for: urls, algorithm: algorithm)
    }
    
    static func exportChecksums(for urls: [URL], algorithm: ChecksumAlgorithm, to outputURL: URL) async throws {
        try await ChecksumService.exportChecksums(for: urls, algorithm: algorithm, to: outputURL)
    }
    
    // MARK: - Temp File Management
    
    static func addTempFile(_ url: URL) {
        TempFileManager.addTempFile(url)
    }
    
    static func removeTempFile(_ url: URL) {
        TempFileManager.removeTempFile(url)
    }
    
    static func cleanupAllTempFiles() {
        TempFileManager.cleanupAllTempFiles()
    }
    
    // MARK: - Utility Methods
    
    static func isNetworkVolume(_ url: URL) -> Bool {
        SafetyValidator.isNetworkVolume(url)
    }
    
    // MARK: - Private Helpers
    
    private static func compareBySizeOnly(leftURL: URL, rightURL: URL, relativePath: String) async -> ResultRow {
        do {
            let leftSize = try leftURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let rightSize = try rightURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            
            let status: ResultRow.Status = leftSize == rightSize ? .match : .sizeMismatch
            return ResultRow(path: relativePath, target: rightURL.path, status: status)
            
        } catch {
            return ResultRow(path: relativePath, target: rightURL.path, status: .contentMismatch)
        }
    }
}

// MARK: - Legacy Support

// Note: The old FileOperationsService.swift should be removed and replaced by this coordinator
// All references to FileOperationsService now point to FileOperationsCoordinator