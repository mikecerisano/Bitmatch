// SharedChecksumService.swift - Platform-agnostic checksum verification
import Foundation
import CryptoKit

/// Shared checksum service that works on both macOS and iOS
class SharedChecksumService: ChecksumService {
    static let shared = SharedChecksumService()
    static var pauseCheck: (@Sendable () async throws -> Void)?
    
    private init() {}
    
    // MARK: - ChecksumService Protocol Implementation
    
    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback? = nil
    ) async throws -> String {
        // Security 9: warn when using deprecated algorithms
        if type.isDeprecated {
            SharedLogger.warning("Using deprecated checksum algorithm \(type.rawValue) – prefer SHA-256 for security", category: .transfer)
        }
        // Use shared cache when possible to avoid recomputation
        if useCache, let cached = await SharedChecksumCache.shared.get(for: fileURL, algorithm: type.rawValue) {
            progressCallback?(1.0, "Using cached checksum")
            return cached
        }
        // iOS: Attempt to start a security scope if one exists.
        // Do not fail if it returns false; sandbox files don't need it.
        #if os(iOS)
        let didStartScope = fileURL.startAccessingSecurityScopedResource()
        defer { if didStartScope { fileURL.stopAccessingSecurityScopedResource() } }
        #endif
        
        let fileSize: Int64
        do {
            fileSize = try getFileSize(for: fileURL)
        } catch {
            throw mapFileOpenError(error, for: fileURL)
        }
        
        let checksum: String = try await {
            switch type {
            case .md5:
                return try await generateMD5(for: fileURL, fileSize: fileSize, progressCallback: progressCallback)
            case .sha256:
                return try await generateSHA256(for: fileURL, fileSize: fileSize, progressCallback: progressCallback)
            case .sha1:
                return try await generateSHA1(for: fileURL, fileSize: fileSize, progressCallback: progressCallback)
            }
        }()
        if useCache {
            await SharedChecksumCache.shared.set(checksum, for: fileURL, algorithm: type.rawValue)
        }
        return checksum
    }

    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        progressCallback: ProgressCallback? = nil
    ) async throws -> String {
        try await generateChecksum(for: fileURL, type: type, useCache: true, progressCallback: progressCallback)
    }
    
    func verifyFileIntegrity(
        sourceURL: URL,
        destinationURL: URL,
        type: ChecksumAlgorithm,
        useCache: Bool,
        progressCallback: ProgressCallback? = nil
    ) async throws -> VerificationResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Generate checksums for both files
        progressCallback?(0.0, "Calculating source checksum...")
        let sourceChecksum = try await generateChecksum(for: sourceURL, type: type, useCache: useCache) { progress, _ in
            progressCallback?(progress * 0.5, "Calculating source checksum...")
        }
        
        progressCallback?(0.5, "Calculating destination checksum...")
        let destinationChecksum = try await generateChecksum(for: destinationURL, type: type, useCache: useCache) { progress, _ in
            progressCallback?(0.5 + progress * 0.5, "Calculating destination checksum...")
        }
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let fileSize = try getFileSize(for: sourceURL)
        
        progressCallback?(1.0, "Verification complete")
        
        return VerificationResult(
            sourceChecksum: sourceChecksum,
            destinationChecksum: destinationChecksum,
            matches: sourceChecksum.lowercased() == destinationChecksum.lowercased(),
            checksumType: type,
            processingTime: processingTime,
            fileSize: fileSize
        )
    }

    func verifyFileIntegrity(
        sourceURL: URL,
        destinationURL: URL,
        type: ChecksumAlgorithm,
        progressCallback: ProgressCallback? = nil
    ) async throws -> VerificationResult {
        try await verifyFileIntegrity(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            type: type,
            useCache: true,
            progressCallback: progressCallback
        )
    }
    
    func performByteComparison(
        sourceURL: URL,
        destinationURL: URL,
        progressCallback: ProgressCallback? = nil
    ) async throws -> Bool {
        // iOS: Attempt to start security scopes if available; proceed if not.
        #if os(iOS)
        let didStartSource = sourceURL.startAccessingSecurityScopedResource()
        let didStartDest = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSource { sourceURL.stopAccessingSecurityScopedResource() }
            if didStartDest { destinationURL.stopAccessingSecurityScopedResource() }
        }
        #endif
        
        let sourceSize = try getFileSize(for: sourceURL)
        let destinationSize = try getFileSize(for: destinationURL)
        
        // Quick size check first
        guard sourceSize == destinationSize else {
            return false
        }
        
        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            throw mapFileOpenError(error, for: sourceURL)
        }
        let destinationHandle: FileHandle
        do {
            destinationHandle = try FileHandle(forReadingFrom: destinationURL)
        } catch {
            closeFileHandle(sourceHandle, context: sourceURL.path)
            throw mapFileOpenError(error, for: destinationURL)
        }

        defer {
            closeFileHandle(sourceHandle, context: sourceURL.path)
            closeFileHandle(destinationHandle, context: destinationURL.path)
        }
        
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < sourceSize {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let sourceData = sourceHandle.readData(ofLength: chunkSize)
            let destinationData = destinationHandle.readData(ofLength: chunkSize)
            
            if sourceData != destinationData {
                return false
            }
            
            bytesProcessed += Int64(sourceData.count)
            
            // Update progress
            let progress = Double(bytesProcessed) / Double(sourceSize)
            progressCallback?(progress, "Comparing bytes...")
        }
        
        return true
    }
    
    // MARK: - Private Implementation
    
    private func getFileSize(for url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func generateMD5(
        for fileURL: URL,
        fileSize: Int64,
        progressCallback: ProgressCallback?
    ) async throws -> String {
        // Use CryptoKit's Insecure.MD5 to avoid CommonCrypto deprecation warnings.
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw mapFileOpenError(error, for: fileURL)
        }
        defer { closeFileHandle(fileHandle, context: fileURL.path) }
        
        var hasher = Insecure.MD5()
        let chunkSize = 64 * 1024
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < fileSize {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            autoreleasepool {
                hasher.update(data: data)
            }
            bytesProcessed += Int64(data.count)
            let progress = Double(bytesProcessed) / Double(fileSize)
            progressCallback?(progress, "Computing MD5 (legacy)...")
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func generateSHA256(
        for fileURL: URL,
        fileSize: Int64,
        progressCallback: ProgressCallback?
    ) async throws -> String {

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw mapFileOpenError(error, for: fileURL)
        }
        defer { closeFileHandle(fileHandle, context: fileURL.path) }
        
        var hasher = SHA256()
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < fileSize {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            
            autoreleasepool {
                hasher.update(data: data)
            }
            bytesProcessed += Int64(data.count)
            
            // Update progress
            let progress = Double(bytesProcessed) / Double(fileSize)
            progressCallback?(progress, "Computing SHA-256...")
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func generateSHA1(
        for fileURL: URL,
        fileSize: Int64,
        progressCallback: ProgressCallback?
    ) async throws -> String {

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw mapFileOpenError(error, for: fileURL)
        }
        defer { closeFileHandle(fileHandle, context: fileURL.path) }

        var hasher = Insecure.SHA1()
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0

        while bytesProcessed < fileSize {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }

            autoreleasepool {
                hasher.update(data: data)
            }

            bytesProcessed += Int64(data.count)

            // Update progress
            let progress = Double(bytesProcessed) / Double(fileSize)
            progressCallback?(progress, "Computing SHA-1...")
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func mapFileOpenError(_ error: Error, for url: URL) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileReadNoSuchFileError {
                return BitMatchError.fileNotFound(url)
            }
            if nsError.code == NSFileReadNoPermissionError {
                return BitMatchError.fileAccessDenied(url)
            }
        }
        return error
    }

    private func closeFileHandle(_ handle: FileHandle, context: String) {
        do {
            try handle.close()
        } catch {
            SharedLogger.warning("Failed to close file handle for \(context): \(error)", category: .transfer)
        }
    }
}
