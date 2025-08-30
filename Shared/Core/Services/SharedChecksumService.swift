// SharedChecksumService.swift - Platform-agnostic checksum verification
import Foundation
import CryptoKit
import CommonCrypto

/// Shared checksum service that works on both macOS and iOS
class SharedChecksumService: ChecksumService {
    static let shared = SharedChecksumService()
    
    private init() {}
    
    // MARK: - ChecksumService Protocol Implementation
    
    func generateChecksum(
        for fileURL: URL,
        type: ChecksumAlgorithm,
        progressCallback: ProgressCallback? = nil
    ) async throws -> String {
        
        // Platform-agnostic security scoped resource access
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw BitMatchError.fileAccessDenied(fileURL)
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        
        let fileSize = try getFileSize(for: fileURL)
        
        switch type {
        case .md5:
            return try await generateMD5(for: fileURL, fileSize: fileSize, progressCallback: progressCallback)
        case .sha256:
            return try await generateSHA256(for: fileURL, fileSize: fileSize, progressCallback: progressCallback)
        case .sha1:
            return try await generateSHA1(for: fileURL, fileSize: fileSize, progressCallback: progressCallback)
        }
    }
    
    func verifyFileIntegrity(
        sourceURL: URL,
        destinationURL: URL,
        type: ChecksumAlgorithm,
        progressCallback: ProgressCallback? = nil
    ) async throws -> VerificationResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Generate checksums for both files
        progressCallback?(0.0, "Calculating source checksum...")
        let sourceChecksum = try await generateChecksum(for: sourceURL, type: type) { progress, _ in
            progressCallback?(progress * 0.5, "Calculating source checksum...")
        }
        
        progressCallback?(0.5, "Calculating destination checksum...")
        let destinationChecksum = try await generateChecksum(for: destinationURL, type: type) { progress, _ in
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
    
    func performByteComparison(
        sourceURL: URL,
        destinationURL: URL,
        progressCallback: ProgressCallback? = nil
    ) async throws -> Bool {
        
        guard sourceURL.startAccessingSecurityScopedResource(),
              destinationURL.startAccessingSecurityScopedResource() else {
            throw BitMatchError.fileAccessDenied(sourceURL)
        }
        defer {
            sourceURL.stopAccessingSecurityScopedResource()
            destinationURL.stopAccessingSecurityScopedResource()
        }
        
        let sourceSize = try getFileSize(for: sourceURL)
        let destinationSize = try getFileSize(for: destinationURL)
        
        // Quick size check first
        guard sourceSize == destinationSize else {
            return false
        }
        
        guard let sourceHandle = try? FileHandle(forReadingFrom: sourceURL),
              let destinationHandle = try? FileHandle(forReadingFrom: destinationURL) else {
            throw BitMatchError.fileNotFound(sourceURL)
        }
        
        defer {
            sourceHandle.closeFile()
            destinationHandle.closeFile()
        }
        
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < sourceSize {
            let sourceData = sourceHandle.readData(ofLength: chunkSize)
            let destinationData = destinationHandle.readData(ofLength: chunkSize)
            
            if sourceData != destinationData {
                return false
            }
            
            bytesProcessed += Int64(sourceData.count)
            
            // Update progress
            let progress = Double(bytesProcessed) / Double(sourceSize)
            progressCallback?(progress, "Comparing bytes...")
            
            // Allow UI updates
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
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
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            throw BitMatchError.fileNotFound(fileURL)
        }
        defer { fileHandle.closeFile() }
        
        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)
        
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < fileSize {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            
            data.withUnsafeBytes { bytes in
                CC_MD5_Update(&context, bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count))
            }
            
            bytesProcessed += Int64(data.count)
            
            // Update progress
            let progress = Double(bytesProcessed) / Double(fileSize)
            progressCallback?(progress, "Computing MD5...")
            
            // Allow UI updates
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, &context)
        
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func generateSHA256(
        for fileURL: URL,
        fileSize: Int64,
        progressCallback: ProgressCallback?
    ) async throws -> String {
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            throw BitMatchError.fileNotFound(fileURL)
        }
        defer { fileHandle.closeFile() }
        
        var hasher = SHA256()
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < fileSize {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            
            hasher.update(data: data)
            bytesProcessed += Int64(data.count)
            
            // Update progress
            let progress = Double(bytesProcessed) / Double(fileSize)
            progressCallback?(progress, "Computing SHA-256...")
            
            // Allow UI updates
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func generateSHA1(
        for fileURL: URL,
        fileSize: Int64,
        progressCallback: ProgressCallback?
    ) async throws -> String {
        
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            throw BitMatchError.fileNotFound(fileURL)
        }
        defer { fileHandle.closeFile() }
        
        var context = CC_SHA1_CTX()
        CC_SHA1_Init(&context)
        
        let chunkSize = 64 * 1024 // 64KB chunks
        var bytesProcessed: Int64 = 0
        
        while bytesProcessed < fileSize {
            let data = fileHandle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            
            data.withUnsafeBytes { bytes in
                CC_SHA1_Update(&context, bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count))
            }
            
            bytesProcessed += Int64(data.count)
            
            // Update progress
            let progress = Double(bytesProcessed) / Double(fileSize)
            progressCallback?(progress, "Computing SHA-1...")
            
            // Allow UI updates
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1_Final(&digest, &context)
        
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}