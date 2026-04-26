// FileCopyService.swift - Atomic file copy with streaming enumeration
// Uses shared AsyncSemaphore from AsyncSemaphore.swift
import Foundation
#if canImport(Darwin)
import Darwin
#endif

final class FileCopyService {
    private actor _EnumeratorSource {
        private let fm = FileManager.default
        private let enumerator: FileManager.DirectoryEnumerator?
        init(base: URL) {
            self.enumerator = fm.enumerator(
                at: base,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: []
            )
        }
        func nextRegularFile() -> URL? {
            while let item = enumerator?.nextObject() as? URL {
                if let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                    if values.isSymbolicLink == true {
                        continue
                    }
                    if values.isRegularFile == true {
                    return item
                    }
                }
            }
            return nil
        }
    }
    // Perf 1: actor wrapping pre-enumerated file list for concurrent worker access
    private actor _ArraySource {
        private let urls: [URL]
        private var index: Int = 0
        init(_ urls: [URL]) { self.urls = urls }
        func next() -> URL? {
            guard index < urls.count else { return nil }
            defer { index += 1 }
            return urls[index]
        }
    }
    static func copyAllSafely(
        from src: URL,
        toRoot dstRoot: URL,
        verificationMode: VerificationMode,
        workers: Int,
        preEnumeratedFiles: [URL]? = nil,
        pauseCheck: (@Sendable () async throws -> Void)? = nil,
        onProgress: @escaping (String, Int64) async -> Void,
        onError: @escaping (String, Error) async -> Void
    ) async throws {
        let fm = FileManager.default
        var dstRootIsDirectory: ObjCBool = false
        if fm.fileExists(atPath: dstRoot.path, isDirectory: &dstRootIsDirectory) {
            guard dstRootIsDirectory.boolValue else {
                throw NSError(
                    domain: "FileCopyService",
                    code: NSFileWriteFileExistsError,
                    userInfo: [NSLocalizedDescriptionKey: "Destination root exists and is not a folder"]
                )
            }
        } else {
            try fm.createDirectory(at: dstRoot, withIntermediateDirectories: true, attributes: nil)
        }

        try await createDirectoryTreeSafely(from: src, toRoot: dstRoot, onError: onError)

        // Streaming copy with bounded concurrency
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Perf 1: use pre-enumerated files when available to avoid redundant filesystem walk
            let nextFile: @Sendable () async -> URL?
            if let preFiles = preEnumeratedFiles {
                let arraySource = _ArraySource(preFiles)
                nextFile = { await arraySource.next() }
            } else {
                let enumSource = _EnumeratorSource(base: src)
                nextFile = { await enumSource.nextRegularFile() }
            }
            let workerCount = max(1, workers)
            for _ in 0..<workerCount {
                group.addTask {
                    let fm = FileManager.default
                    while true {
                        try Task.checkCancellation()
                        if let pauseCheck = pauseCheck {
                            try await pauseCheck()
                        }
                        guard let fileURL = await nextFile() else { break }
                        // Compute relative path before do block so it's available in catch
                        // Fallback to lastPathComponent if file isn't under src (symlinks, etc.)
                        let relPath: String = {
                            let srcPath = src.path
                            let filePath = fileURL.path
                            if filePath.hasPrefix(srcPath + "/") {
                                return String(filePath.dropFirst(srcPath.count + 1))
                            } else {
                                return fileURL.lastPathComponent
                            }
                        }()
                        // Security 11: reject path traversal components
                        if relPath.split(separator: "/").contains("..") {
                            await onError(relPath, NSError(
                                domain: "FileCopyService",
                                code: NSFileWriteNoPermissionError,
                                userInfo: [NSLocalizedDescriptionKey: "Path contains traversal component (..)"]
                            ))
                            continue
                        }
                        // Security 11: verify resolved source is under source root
                        let resolvedSource = fileURL.resolvingSymlinksInPath()
                        let resolvedSrcRoot = src.resolvingSymlinksInPath()
                        guard Self.pathIsWithin(resolvedSource.path, root: resolvedSrcRoot.path) else {
                            await onError(relPath, NSError(
                                domain: "FileCopyService",
                                code: NSFileWriteNoPermissionError,
                                userInfo: [NSLocalizedDescriptionKey: "Source file resolves outside source directory"]
                            ))
                            continue
                        }
                        do {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                            let dstURL = dstRoot.appendingPathComponent(relPath)
                            let parentDir = dstURL.deletingLastPathComponent()
                            // Security: Resolve symlinks in destination path to prevent writes outside intended directory
                            let realParentDirURL = parentDir.standardized.resolvingSymlinksInPath()
                            let realDstRootURL = dstRoot.standardized.resolvingSymlinksInPath()

                            guard Self.pathIsWithin(realParentDirURL.path, root: realDstRootURL.path) else {
                                await onError(relPath, NSError(
                                    domain: "FileCopyService",
                                    code: NSFileWriteNoPermissionError,
                                    userInfo: [NSLocalizedDescriptionKey: "Destination path escapes root directory"]
                                ))
                                continue
                            }
                            if !fm.fileExists(atPath: parentDir.path) {
                                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                            }
                            let resolvedParentAfterCreate = parentDir.standardized.resolvingSymlinksInPath()
                            guard Self.pathIsWithin(resolvedParentAfterCreate.path, root: realDstRootURL.path) else {
                                await onError(relPath, NSError(
                                    domain: "FileCopyService",
                                    code: NSFileWriteNoPermissionError,
                                    userInfo: [NSLocalizedDescriptionKey: "Destination directory changed while preparing copy"]
                                ))
                                continue
                            }
                            let sourceSize = Int64(resourceValues.fileSize ?? 0)
                            if fm.fileExists(atPath: dstURL.path) {
                                let shouldReuseExisting = try await Self.canReuseExistingDestinationFile(
                                    source: fileURL,
                                    destination: dstURL,
                                    sourceSize: sourceSize,
                                    sourceModificationDate: resourceValues.contentModificationDate,
                                    verificationMode: verificationMode
                                )
                                if shouldReuseExisting {
                                    await onProgress(relPath, sourceSize)
                                    continue
                                }
                            }
                            try await copyFileSecurely(from: fileURL, to: dstURL, pauseCheck: pauseCheck)
                            await onProgress(relPath, sourceSize)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            await onError(relPath, error)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    private static func copyFileSecurely(
        from source: URL,
        to destination: URL,
        pauseCheck: (@Sendable () async throws -> Void)?
    ) async throws {
        let fm = FileManager.default
        let srcHandle = try FileHandle(forReadingFrom: source)
        defer { closeFileHandle(srcHandle, context: source.path) }
        let tempName = ".bitmatch.tmp." + UUID().uuidString
        let tempURL = destination.deletingLastPathComponent().appendingPathComponent(tempName)
        // Security 12: set restrictive permissions on temp files
        fm.createFile(atPath: tempURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        guard let dstHandle = FileHandle(forWritingAtPath: tempURL.path) else {
            removeTempItemIfPresent(at: tempURL)
            throw NSError(domain: "FileCopyService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to open temp destination for writing"])
        }
        var replaceSucceeded = false
        defer {
            closeFileHandle(dstHandle, context: tempURL.path)
            if !replaceSucceeded { removeTempItemIfPresent(at: tempURL) }
        }
        let bufferSize = 4 * 1024 * 1024 // Perf 3: 4MB chunk for better throughput
        // Get source attributes at START - captures original state before any race conditions
        let sourceAttributes = try fm.attributesOfItem(atPath: source.path)
        let sourceSize = (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0
        let sourceModificationDate = sourceAttributes[.modificationDate] as? Date
        let sourceIdentity = fileIdentity(from: sourceAttributes)
        let logInterval: Int64 = 512 * 1024 * 1024
        var bytesCopied: Int64 = 0
        var nextLogMark = logInterval
        let shouldLog = sourceSize >= logInterval
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        if shouldLog {
            Self.logMemoryUsage(context: "start copy \(source.lastPathComponent)")
        }
        var reachedEOF = false
        while !reachedEOF {
            try Task.checkCancellation()
            if let pauseCheck = pauseCheck {
                try await pauseCheck()
            }
            var localError: Error?
            var chunkSize: Int = 0
            // Autorelease scope keeps chunk Data from piling up on massive transfers
            autoreleasepool {
                do {
                    guard let data = try srcHandle.read(upToCount: bufferSize), !data.isEmpty else {
                        reachedEOF = true
                        return
                    }
                    chunkSize = data.count
                    try dstHandle.write(contentsOf: data)
                } catch {
                    localError = error
                    reachedEOF = true
                }
            }
            if let error = localError {
                throw error
            }
            if chunkSize == 0 {
                break
            }
            bytesCopied += Int64(chunkSize)
            if shouldLog, bytesCopied >= nextLogMark {
                let copiedString = sizeFormatter.string(fromByteCount: bytesCopied)
                let totalString = sizeFormatter.string(fromByteCount: sourceSize)
                Self.logMemoryUsage(context: "\(source.lastPathComponent) – \(copiedString)/\(totalString)")
                nextLogMark += logInterval
            }
        }
        #if compiler(>=5.7)
        if #available(iOS 16.0, macOS 13.0, *) {
            do {
                try dstHandle.synchronize()
            } catch {
                throw NSError(
                    domain: "FileCopyService",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to flush destination file: \(error.localizedDescription)"]
                )
            }
        } else {
            dstHandle.synchronizeFile()
        }
        #else
        dstHandle.synchronizeFile()
        #endif
        let tempAttributes = try fm.attributesOfItem(atPath: tempURL.path)
        let tempSize = (tempAttributes[.size] as? NSNumber)?.int64Value ?? 0
        guard sourceSize == tempSize else {
            throw NSError(domain: "FileCopyService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Size mismatch after copy"])
        }

        let finalSourceAttributes = try fm.attributesOfItem(atPath: source.path)
        guard sourceRemainedStable(
            initialSize: sourceSize,
            initialModificationDate: sourceModificationDate,
            initialIdentity: sourceIdentity,
            finalAttributes: finalSourceAttributes
        ) else {
            throw NSError(
                domain: "FileCopyService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Source file changed during copy; destination was not modified"]
            )
        }

        guard !fm.fileExists(atPath: destination.path) else {
            throw NSError(
                domain: "FileCopyService",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Destination file appeared during copy; refusing to overwrite it"]
            )
        }

        // Publish only when the final path is still empty. moveItem refuses to
        // replace an existing file, so a race creates a copy error instead of
        // clobbering someone else's destination item.
        try fm.moveItem(at: tempURL, to: destination)
        replaceSucceeded = true

        // Restore original modification time from source file
        // This is critical for quick-mode resume to work correctly (mtime comparison)
        // Using try? so metadata failure doesn't fail an otherwise successful copy
        if let modDate = sourceModificationDate {
            do {
                try fm.setAttributes([.modificationDate: modDate], ofItemAtPath: destination.path)
            } catch {
                SharedLogger.warning("Failed to restore modification date on \(destination.path): \(error)", category: .transfer)
            }
        }

        if shouldLog {
            Self.logMemoryUsage(context: "completed \(destination.lastPathComponent)")
        }
    }

    private static func createDirectoryTreeSafely(
        from sourceRoot: URL,
        toRoot destinationRoot: URL,
        onError: @escaping (String, Error) async -> Void
    ) async throws {
        let fm = FileManager.default
        let sourceRootPath = sourceRoot.path
        let destinationRootPath = destinationRoot.standardized.resolvingSymlinksInPath().path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return }

        while let item = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard let values = try? item.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true,
                  values.isDirectory == true else {
                continue
            }

            let itemPath = item.path
            let relPath: String
            if itemPath.hasPrefix(sourceRootPath + "/") {
                relPath = String(itemPath.dropFirst(sourceRootPath.count + 1))
            } else {
                relPath = item.lastPathComponent
            }

            guard !relPath.split(separator: "/").contains("..") else {
                await onError(relPath, NSError(
                    domain: "FileCopyService",
                    code: NSFileWriteNoPermissionError,
                    userInfo: [NSLocalizedDescriptionKey: "Directory path contains traversal component (..)"]
                ))
                continue
            }

            let destinationDirectory = destinationRoot.appendingPathComponent(relPath, isDirectory: true)
            let resolvedDestination = destinationDirectory.standardized.resolvingSymlinksInPath()
            guard pathIsWithin(resolvedDestination.path, root: destinationRootPath) else {
                await onError(relPath, NSError(
                    domain: "FileCopyService",
                    code: NSFileWriteNoPermissionError,
                    userInfo: [NSLocalizedDescriptionKey: "Destination directory escapes root directory"]
                ))
                continue
            }

            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    await onError(relPath, existingDestinationConflictError("Existing destination item conflicts with source directory"))
                }
                continue
            }

            do {
                try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                await onError(relPath, error)
            }
        }
    }

    private static func closeFileHandle(_ handle: FileHandle, context: String) {
        do {
            try handle.close()
        } catch {
            SharedLogger.warning("Failed to close file handle for \(context): \(error)", category: .transfer)
        }
    }

    private static func removeTempItemIfPresent(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            SharedLogger.warning("Failed to remove temp file at \(url.path): \(error)", category: .transfer)
        }
    }

    private static let modificationTolerance: TimeInterval = 2.0

    private static func canReuseExistingDestinationFile(
        source: URL,
        destination: URL,
        sourceSize: Int64,
        sourceModificationDate: Date?,
        verificationMode: VerificationMode
    ) async throws -> Bool {
        let fm = FileManager.default
        let destinationValues = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard destinationValues.isSymbolicLink != true, destinationValues.isRegularFile == true else {
            throw existingDestinationConflictError("Existing destination item is not a regular file")
        }

        let destAttributes = try fm.attributesOfItem(atPath: destination.path)
        let destSize = (destAttributes[.size] as? NSNumber)?.int64Value ?? -1
        guard destSize == sourceSize else {
            throw existingDestinationConflictError("Existing destination file differs in size")
        }

        if verificationMode == .quick {
            let destModDate = destAttributes[.modificationDate] as? Date
            guard modificationDatesMatch(source: sourceModificationDate, destination: destModDate) else {
                throw existingDestinationConflictError("Existing destination file differs; choose an empty destination or a unique folder name")
            }
            return true
        }

        guard try await checksumsMatch(
            source: source,
            destination: destination,
            verificationMode: verificationMode
        ) else {
            throw existingDestinationConflictError("Existing destination file checksum differs; refusing to overwrite it")
        }

        return true
    }

    private static func existingDestinationConflictError(_ reason: String) -> NSError {
        NSError(
            domain: "FileCopyService",
            code: NSFileWriteFileExistsError,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }

    /// Security: compare path-components, not raw prefixes, to avoid boundary bypasses.
    private static func pathIsWithin(_ candidatePath: String, root rootPath: String) -> Bool {
        let candidateComponents = URL(fileURLWithPath: candidatePath).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: rootPath).standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy(==)
    }

    private static func modificationDatesMatch(source: Date?, destination: Date?) -> Bool {
        guard let source, let destination else { return false }
        return abs(source.timeIntervalSince(destination)) <= modificationTolerance
    }

    private static func checksumsMatch(
        source: URL,
        destination: URL,
        verificationMode: VerificationMode
    ) async throws -> Bool {
        let types = verificationMode.checksumTypes
        guard !types.isEmpty else { return false }
        for type in types {
            let srcHash = try await SharedChecksumService.shared.generateChecksum(
                for: source,
                type: type,
                useCache: false,
                progressCallback: nil
            )
            let dstHash = try await SharedChecksumService.shared.generateChecksum(
                for: destination,
                type: type,
                useCache: false,
                progressCallback: nil
            )
            if srcHash.lowercased() != dstHash.lowercased() {
                return false
            }
        }
        return true
    }

    private static func fileIdentity(from attributes: [FileAttributeKey: Any]) -> (volume: UInt64?, file: UInt64?) {
        let volume = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        let file = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        return (volume, file)
    }

    private static func sourceRemainedStable(
        initialSize: Int64,
        initialModificationDate: Date?,
        initialIdentity: (volume: UInt64?, file: UInt64?),
        finalAttributes: [FileAttributeKey: Any]
    ) -> Bool {
        let finalSize = (finalAttributes[.size] as? NSNumber)?.int64Value ?? -1
        guard finalSize == initialSize else { return false }

        let finalIdentity = fileIdentity(from: finalAttributes)
        if let initialVolume = initialIdentity.volume, let finalVolume = finalIdentity.volume, initialVolume != finalVolume {
            return false
        }
        if let initialFile = initialIdentity.file, let finalFile = finalIdentity.file, initialFile != finalFile {
            return false
        }

        let finalModificationDate = finalAttributes[.modificationDate] as? Date
        return initialModificationDate == finalModificationDate
    }
}

#if canImport(Darwin)
extension FileCopyService {
    private static func logMemoryUsage(context: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<Int32>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return }
        let usedMB = Double(info.resident_size) / 1_048_576.0
        let formatted = String(format: "%.2f", usedMB)
        SharedLogger.debug("Memory [\(context)]: \(formatted) MB resident", category: .transfer)
    }
}
#else
extension FileCopyService {
    private static func logMemoryUsage(context: String) {}
}
#endif
