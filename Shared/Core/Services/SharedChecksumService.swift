// SharedChecksumService.swift - Platform-agnostic checksum verification
import Foundation
import CryptoKit

/// Shared checksum service that works on both macOS and iOS
class SharedChecksumService: ChecksumService {
    static let shared = SharedChecksumService()
    static var pauseCheck: (@Sendable () async throws -> Void)?

    private struct FileReadSnapshot: Equatable {
        let size: Int64
        let modificationDate: Date?
        let systemFileNumber: UInt64?
    }
    
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
        
        let initialSnapshot: FileReadSnapshot
        do {
            initialSnapshot = try captureSnapshot(for: fileURL)
        } catch {
            throw mapFileOpenError(error, for: fileURL)
        }
        
        let checksum: String = try await {
            switch type {
            case .md5:
                return try await generateMD5(for: fileURL, initial: initialSnapshot, progressCallback: progressCallback)
            case .sha256:
                return try await generateSHA256(for: fileURL, initial: initialSnapshot, progressCallback: progressCallback)
            case .sha1:
                return try await generateSHA1(for: fileURL, initial: initialSnapshot, progressCallback: progressCallback)
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
        // Keep pair-wide snapshots inside the same security scopes as the hashes.
        #if os(iOS)
        let didStartSource = sourceURL.startAccessingSecurityScopedResource()
        let didStartDest = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSource { sourceURL.stopAccessingSecurityScopedResource() }
            if didStartDest { destinationURL.stopAccessingSecurityScopedResource() }
        }
        #endif
        
        let startTime = CFAbsoluteTimeGetCurrent()

        let sourceInitial = try captureSnapshot(for: sourceURL)
        let destinationInitial = try captureSnapshot(for: destinationURL)
        
        // Generate checksums for both files
        progressCallback?(0.0, "Calculating source checksum...")
        let sourceChecksum = try await generateChecksum(for: sourceURL, type: type, useCache: useCache) { progress, _ in
            progressCallback?(progress * 0.5, "Calculating source checksum...")
        }
        
        progressCallback?(0.5, "Calculating destination checksum...")
        let destinationChecksum = try await generateChecksum(for: destinationURL, type: type, useCache: useCache) { progress, _ in
            progressCallback?(0.5 + progress * 0.5, "Calculating destination checksum...")
        }

        try validateUnchangedSnapshot(of: sourceURL, initial: sourceInitial)
        try validateUnchangedSnapshot(of: destinationURL, initial: destinationInitial)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let fileSize = sourceInitial.size
        
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
        
        let sourceInitial = try captureSnapshot(for: sourceURL)
        let destinationInitial = try captureSnapshot(for: destinationURL)
        
        // Quick size check first
        guard sourceInitial.size == destinationInitial.size else {
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

        while bytesProcessed < sourceInitial.size {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let sourceData = try sourceHandle.read(upToCount: chunkSize) ?? Data()
            let destinationData = try destinationHandle.read(upToCount: chunkSize) ?? Data()

            // EOF before the expected size means a file shrank mid-compare;
            // surface it instead of returning a verdict (or looping forever).
            if sourceData.isEmpty || destinationData.isEmpty {
                throw Self.truncatedReadError(
                    for: sourceData.isEmpty ? sourceURL : destinationURL,
                    expected: sourceInitial.size,
                    actual: bytesProcessed
                )
            }

            if sourceData != destinationData {
                try validateUnchangedSnapshot(of: sourceURL, initial: sourceInitial)
                try validateUnchangedSnapshot(of: destinationURL, initial: destinationInitial)
                return false
            }

            bytesProcessed += Int64(sourceData.count)

            // Update progress
            let progress = Double(bytesProcessed) / Double(sourceInitial.size)
            progressCallback?(progress, "Comparing bytes...")
        }

        let sourceTrailingData = try sourceHandle.read(upToCount: 1) ?? Data()
        let destinationTrailingData = try destinationHandle.read(upToCount: 1) ?? Data()
        try validateStableRead(
            of: sourceURL,
            initial: sourceInitial,
            bytesRead: bytesProcessed,
            trailingData: sourceTrailingData
        )
        try validateStableRead(
            of: destinationURL,
            initial: destinationInitial,
            bytesRead: bytesProcessed,
            trailingData: destinationTrailingData
        )

        return true
    }
    
    // MARK: - Private Implementation
    
    private func captureSnapshot(for url: URL) throws -> FileReadSnapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileReadSnapshot(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date,
            systemFileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }

    private func validateStableRead(
        of url: URL,
        initial: FileReadSnapshot,
        bytesRead: Int64,
        trailingData: Data
    ) throws {
        guard bytesRead == initial.size, trailingData.isEmpty else {
            throw NSError(
                domain: "SharedChecksumService",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "File changed while reading \(url.lastPathComponent)"]
            )
        }
        try validateUnchangedSnapshot(of: url, initial: initial)
    }

    private func validateUnchangedSnapshot(
        of url: URL,
        initial: FileReadSnapshot
    ) throws {
        guard try captureSnapshot(for: url) == initial else {
            throw NSError(
                domain: "SharedChecksumService",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "File changed while reading \(url.lastPathComponent)"]
            )
        }
    }
    
    private func generateMD5(
        for fileURL: URL,
        initial: FileReadSnapshot,
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

        while bytesProcessed < initial.size {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let data = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            autoreleasepool {
                hasher.update(data: data)
            }
            bytesProcessed += Int64(data.count)
            let progress = Double(bytesProcessed) / Double(initial.size)
            progressCallback?(progress, "Computing MD5 (legacy)...")
        }
        let trailingData = try fileHandle.read(upToCount: 1) ?? Data()
        try validateStableRead(
            of: fileURL,
            initial: initial,
            bytesRead: bytesProcessed,
            trailingData: trailingData
        )

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func generateSHA256(
        for fileURL: URL,
        initial: FileReadSnapshot,
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

        while bytesProcessed < initial.size {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let data = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }

            autoreleasepool {
                hasher.update(data: data)
            }
            bytesProcessed += Int64(data.count)

            // Update progress
            let progress = Double(bytesProcessed) / Double(initial.size)
            progressCallback?(progress, "Computing SHA-256...")
        }
        let trailingData = try fileHandle.read(upToCount: 1) ?? Data()
        try validateStableRead(
            of: fileURL,
            initial: initial,
            bytesRead: bytesProcessed,
            trailingData: trailingData
        )

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func generateSHA1(
        for fileURL: URL,
        initial: FileReadSnapshot,
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

        while bytesProcessed < initial.size {
            await Task.yield()
            try Task.checkCancellation()
            if let pauseCheck = Self.pauseCheck {
                try await pauseCheck()
            }
            let data = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }

            autoreleasepool {
                hasher.update(data: data)
            }

            bytesProcessed += Int64(data.count)

            // Update progress
            let progress = Double(bytesProcessed) / Double(initial.size)
            progressCallback?(progress, "Computing SHA-1...")
        }
        let trailingData = try fileHandle.read(upToCount: 1) ?? Data()
        try validateStableRead(
            of: fileURL,
            initial: initial,
            bytesRead: bytesProcessed,
            trailingData: trailingData
        )

        let digest = hasher.finalize()
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private static func truncatedReadError(for url: URL, expected: Int64, actual: Int64) -> Error {
        NSError(
            domain: "SharedChecksumService",
            code: -10,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "File changed while reading \(url.lastPathComponent): expected \(expected) bytes, read \(actual)"
            ]
        )
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
