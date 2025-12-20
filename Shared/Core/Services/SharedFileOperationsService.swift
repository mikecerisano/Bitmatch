// SharedFileOperationsService.swift - Platform-agnostic file operations
// Uses shared AsyncSemaphore from AsyncSemaphore.swift
import Foundation

// Thread-safe accumulator for results coalescing (copy → verified)
actor ResultStore {
    private var list: [FileOperationResult] = []
    // Bound memory: keep only the most recent N results
    private let maxCapacity: Int
    init(maxCapacity: Int = 10_000) { self.maxCapacity = max(1, maxCapacity) }

    func upsert(_ r: FileOperationResult) {
        if let idx = list.lastIndex(where: { $0.sourceURL == r.sourceURL && $0.destinationURL == r.destinationURL }) {
            list[idx] = r
        } else {
            list.append(r)
            if list.count > maxCapacity {
                let overflow = list.count - maxCapacity
                list.removeFirst(overflow)
            }
        }
    }
    func snapshot() -> [FileOperationResult] { list }
}

actor VerifyCounter {
    private var value: Int = 0

    func reset() {
        value = 0
    }

    func increment() -> Int {
        value += 1
        return value
    }

    func current() -> Int {
        value
    }
}

class SharedFileOperationsService: FileOperationsService {
    typealias ProgressCallback = (OperationProgress) -> Void

    private let fileSystem: FileSystemService
    private let checksumService: any ChecksumService
    private var currentOperation: Task<FileOperation, Error>?
    private let pauseState = PauseState()
    private let verifyCounter = VerifyCounter()

    /// Thread-safe pause state management
    private actor PauseState {
        private var paused = false
        func isPaused() -> Bool { paused }
        func pause() { paused = true }
        func resume() { paused = false }
    }
    
    init(fileSystem: FileSystemService, checksum: any ChecksumService) {
        self.fileSystem = fileSystem
        self.checksumService = checksum
    }
    
    // MARK: - FileOperationsService Protocol Implementation
    
    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64? = nil,
        progressCallback: @escaping ProgressCallback,
        onFileResult: ((FileOperationResult) -> Void)?
    ) async throws -> FileOperation {
        
        // Cancel any existing operation
        cancelOperation()
        
        let operation = FileOperation(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            startTime: Date(),
            endTime: nil,
            results: [],
            verificationMode: verificationMode,
            settings: settings,
            estimatedTotalBytes: estimatedTotalBytes
        )
        
        let operationTask = Task {
            return try await executeOperation(operation, progressCallback: progressCallback, onFileResult: onFileResult)
        }
        currentOperation = operationTask

        return try await operationTask.value
    }
    
    func cancelOperation() {
        currentOperation?.cancel()
        currentOperation = nil
    }
    
    func pauseOperation() async {
        await pauseState.pause()
    }

    func resumeOperation() async {
        await pauseState.resume()
    }

    private func waitIfPaused() async throws {
        while await pauseState.isPaused() && !Task.isCancelled {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
    
    // MARK: - Private Implementation
    
    private func executeOperation(
        _ operation: FileOperation,
        progressCallback: @escaping ProgressCallback,
        onFileResult: ((FileOperationResult) -> Void)?
    ) async throws -> FileOperation {
        
        // Use a result store to coalesce rows safely across concurrent verification tasks
        let resultStore = ResultStore()
        
        // Step 1: Validate access to all URLs
        progressCallback(OperationProgress(
            overallProgress: 0.0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: 0,
            currentStage: .preparing,
            speed: nil,
            timeRemaining: nil
        ))

        await verifyCounter.reset()
        SharedChecksumService.pauseCheck = { [weak self] in
            guard let self else { return }
            try await self.waitIfPaused()
        }
        let didStartSourceScope = fileSystem.startAccessing(url: operation.sourceURL)
        var destinationScopes: [URL: Bool] = [:]
        for destinationURL in operation.destinationURLs {
            destinationScopes[destinationURL] = fileSystem.startAccessing(url: destinationURL)
        }
        defer {
            SharedChecksumService.pauseCheck = nil
            if didStartSourceScope { fileSystem.stopAccessing(url: operation.sourceURL) }
            for (url, didStart) in destinationScopes where didStart {
                fileSystem.stopAccessing(url: url)
            }
        }
        
        SharedLogger.debug("Validating access to source: \(operation.sourceURL.path)", category: .transfer)
        guard await fileSystem.validateFileAccess(url: operation.sourceURL) else {
            throw BitMatchError.fileAccessDenied(operation.sourceURL)
        }
        
        for destinationURL in operation.destinationURLs {
            SharedLogger.debug("Validating access to destination: \(destinationURL.path)", category: .transfer)
            guard await fileSystem.validateFileAccess(url: destinationURL) else {
                throw BitMatchError.fileAccessDenied(destinationURL)
            }
        }
        
        // Step 2: Determine file counts without materializing full lists (streaming enumeration)
        SharedLogger.debug("Prep: counting files at \(operation.sourceURL.path)", category: .transfer)
        let perSourceFileCount = FileTreeEnumerator.countRegularFiles(base: operation.sourceURL)
        let totalFiles = perSourceFileCount * operation.destinationURLs.count
        SharedLogger.debug("Prep: source files=\(perSourceFileCount), destinations=\(operation.destinationURLs.count), planned total rows=\(totalFiles)", category: .transfer)
        var processedFiles = 0
        let destinationCount = operation.destinationURLs.count
        var perDestinationCompleted = Array(repeating: 0, count: destinationCount)
        let perDestinationTotals = Array(repeating: perSourceFileCount, count: destinationCount)
        let totalStageUnits = operation.verificationMode == .quick ? 1 : 2
        
        // Step 2a: Validate sufficient storage space
        // Calculate total size if not provided
        let totalSizeBytes: Int64
        if let estimated = operation.estimatedTotalBytes {
            totalSizeBytes = estimated
        } else {
            SharedLogger.debug("Calculating total size for space check...", category: .transfer)
            // Quick enumeration to sum size
            var size: Int64 = 0
            if let enumerator = FileManager.default.enumerator(
                at: operation.sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { throw CancellationError() }
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                       resourceValues.isRegularFile == true {
                        size += Int64(resourceValues.fileSize ?? 0)
                    }
                }
            }
            totalSizeBytes = size
        }
        
        for (index, destinationURL) in operation.destinationURLs.enumerated() {
            let available = fileSystem.freeSpace(at: destinationURL)
            SharedLogger.debug("Storage check dest #\(index+1): need \(totalSizeBytes), have \(available)", category: .transfer)
            
            // Add 100MB buffer for overhead/filesystem structures
            if available < (totalSizeBytes + 100 * 1024 * 1024) {
                throw BitMatchError.insufficientStorage(totalSizeBytes, available)
            }
        }
        
        // Step 3: Copy files to each destination
        let startTime = Date()
        var totalBytesProcessed: Int64 = 0
        // Feature flag for pipelined verification; defaults to off
        let shouldPipelineVerify = UserDefaults.standard.bool(forKey: "EnablePipelinedVerify")
        // Conservative default: at most 2 concurrent verifies total
        let verifySemaphore = AsyncSemaphore(count: shouldPipelineVerify ? 2 : 0)
        var verifyTasks: [Task<Void, Never>] = []
        let maxQueuedVerifyTasks = 200
        defer {
            for task in verifyTasks {
                task.cancel()
            }
        }
        var lastCopyLogCount = 0
        
        // Skip heavy pre-scan to reduce memory and start copying sooner

        for (destIndex, destinationURL) in operation.destinationURLs.enumerated() {
            // Compute destination root folder, honoring camera grouping settings
            let cardName = operation.sourceURL.lastPathComponent
            let labeledCardName = operation.settings.formattedFolderName(for: cardName)
            let destFolder: URL = {
                if operation.settings.groupByCamera {
                    let raw = operation.settings.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    let group = raw.isEmpty ? "Camera" : raw
                    return destinationURL.appendingPathComponent(group).appendingPathComponent(cardName)
                } else {
                    let folderName = labeledCardName.isEmpty ? cardName : labeledCardName
                    return destinationURL.appendingPathComponent(folderName)
                }
            }()
            try fileSystem.createDirectory(at: destFolder)

            SharedLogger.info("➡️ Starting destination \(destIndex + 1)/\(destinationCount): \(destFolder.path)", category: .transfer)
            if destIndex < perDestinationTotals.count && destIndex < perDestinationCompleted.count {
                let seededCompleted = perDestinationCompleted[destIndex]
                let seededTotal = perDestinationTotals[destIndex]
                SharedLogger.debug("   Resume seed on destination: \(seededCompleted)/\(seededTotal) files already present", category: .transfer)
            }

            // Copy to this destination using atomic writes and resume-aware skip
            SharedLogger.info("→ Begin copy to dest #\(destIndex + 1)/\(destinationCount): \(destFolder.path)", category: .transfer)
            try await FileCopyService.copyAllSafely(
                from: operation.sourceURL,
                toRoot: destFolder,
                workers: 1,
                preEnumeratedFiles: nil,
                pauseCheck: { [weak self] in
                    guard let self else { return }
                    try await self.waitIfPaused()
                },
                onProgress: { fileName, fileSize in
                    processedFiles += 1
                    if destIndex < perDestinationCompleted.count { perDestinationCompleted[destIndex] += 1 }
                    totalBytesProcessed += max(0, fileSize)
                    if processedFiles - lastCopyLogCount >= 25 || processedFiles == totalFiles {
                        let formatted = ByteCountFormatter.string(fromByteCount: totalBytesProcessed, countStyle: .file)
                        SharedLogger.debug("Copy progress: files=\(processedFiles)/\(totalFiles) bytes=\(formatted)", category: .transfer)
                        lastCopyLogCount = processedFiles
                    }
                    // fileName here is the relative path; emit per-file copy result, and enqueue verify if enabled
                    let relativePath = fileName
                    let srcURL = operation.sourceURL.appendingPathComponent(relativePath)
                    let dstURL = destFolder.appendingPathComponent(relativePath)
                    let copyResult = FileOperationResult(
                        sourceURL: srcURL,
                        destinationURL: dstURL,
                        success: true,
                        error: nil,
                        fileSize: max(0, fileSize),
                        verificationResult: nil,
                        processingTime: 0
                    )
                    onFileResult?(copyResult)

                    if shouldPipelineVerify {
                        let mode = operation.verificationMode
                        verifyTasks.append(Task { [verifySemaphore] in
                            await verifySemaphore.wait()
                            do {
                                try Task.checkCancellation()
                                try await self.waitIfPaused()
                                var verificationResult: VerificationResult?
                                if mode == .thorough {
                                    var combinedMatches = true
                                    var primaryResult: VerificationResult?
                                    var totalProcessing: TimeInterval = 0
                                    for type in mode.checksumTypes {
                                        let res = try await self.checksumService.verifyFileIntegrity(
                                            sourceURL: srcURL,
                                            destinationURL: dstURL,
                                            type: type,
                                            progressCallback: nil
                                        )
                                        combinedMatches = combinedMatches && res.matches
                                        totalProcessing += res.processingTime
                                        if type == .sha256 { primaryResult = res }
                                    }
                                    if let baseRes = primaryResult {
                                        verificationResult = VerificationResult(
                                            sourceChecksum: baseRes.sourceChecksum,
                                            destinationChecksum: baseRes.destinationChecksum,
                                            matches: combinedMatches,
                                            checksumType: baseRes.checksumType,
                                            processingTime: totalProcessing,
                                            fileSize: baseRes.fileSize
                                        )
                                    } else {
                                        let firstType = mode.checksumTypes.first ?? .sha256
                                        verificationResult = try await self.checksumService.verifyFileIntegrity(
                                            sourceURL: srcURL,
                                            destinationURL: dstURL,
                                            type: firstType,
                                            progressCallback: nil
                                        )
                                    }
                                } else if mode.useChecksum {
                                    let t = mode.checksumTypes.first ?? .sha256
                                    verificationResult = try await self.checksumService.verifyFileIntegrity(
                                        sourceURL: srcURL,
                                        destinationURL: dstURL,
                                        type: t,
                                        progressCallback: nil
                                    )
                                }
                                let verified = FileOperationResult(
                                    sourceURL: srcURL,
                                    destinationURL: dstURL,
                                    success: true,
                                    error: nil,
                                    fileSize: max(0, fileSize),
                                    verificationResult: verificationResult,
                                    processingTime: 0
                                )
                                let verifiedCount = await self.verifyCounter.increment()
                                let elapsedTime = Date().timeIntervalSince(startTime)
                                let speed = elapsedTime > 0 ? Double(totalBytesProcessed) / elapsedTime : nil
                                let estimatedTotalBytes: Int64 = {
                                    if let etb = operation.estimatedTotalBytes, etb > 0 { return etb }
                                    if processedFiles > 0 {
                                        let avg = totalBytesProcessed / Int64(processedFiles)
                                        return Int64(totalFiles) * avg
                                    }
                                    return 50 * 1024 * 1024 * Int64(totalFiles)
                                }()
                                let timeRemaining = speed != nil && speed! > 0 ? Double(estimatedTotalBytes - totalBytesProcessed) / speed! : nil
                                let overall = Double(processedFiles + verifiedCount) / Double(max(1, totalFiles * totalStageUnits))
                                progressCallback(OperationProgress(
                                    overallProgress: overall,
                                    currentFile: srcURL.lastPathComponent,
                                    filesProcessed: processedFiles,
                                    totalFiles: totalFiles,
                                    currentStage: .verifying,
                                    speed: speed,
                                    timeRemaining: timeRemaining,
                                    elapsedTime: elapsedTime,
                                    averageSpeed: speed,
                                    peakSpeed: nil,
                                    bytesProcessed: totalBytesProcessed,
                                    totalBytes: estimatedTotalBytes,
                                    stageProgress: Double(verifiedCount) / Double(max(1, totalFiles)),
                                    reusedCopies: nil,
                                    perDestinationTotals: perDestinationTotals,
                                    perDestinationCompleted: perDestinationCompleted
                                ))
                                await resultStore.upsert(verified)
                                onFileResult?(verified)
                            } catch is CancellationError {
                                // Skip result on cancellation
                            } catch {
                                let failure = FileOperationResult(
                                    sourceURL: srcURL,
                                    destinationURL: dstURL,
                                    success: false,
                                    error: error,
                                    fileSize: 0,
                                    verificationResult: nil,
                                    processingTime: 0
                                )
                                _ = await self.verifyCounter.increment()
                                await resultStore.upsert(failure)
                                onFileResult?(failure)
                            }
                            await verifySemaphore.signal()
                        })
                        if verifyTasks.count >= maxQueuedVerifyTasks {
                            let next = verifyTasks.removeFirst()
                            await next.value
                        }
                    }
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    let speed = elapsedTime > 0 ? Double(totalBytesProcessed) / elapsedTime : nil
                    let estimatedTotalBytes: Int64 = {
                        if let etb = operation.estimatedTotalBytes, etb > 0 { return etb }
                        if processedFiles > 0 {
                            let avg = totalBytesProcessed / Int64(processedFiles)
                            return Int64(totalFiles) * avg
                        }
                        return 50 * 1024 * 1024 * Int64(totalFiles)
                    }()
                    let timeRemaining = speed != nil && speed! > 0 ? Double(estimatedTotalBytes - totalBytesProcessed) / speed! : nil
                    let overall = Double(processedFiles) / Double(max(1, totalFiles * totalStageUnits))
                    progressCallback(OperationProgress(
                        overallProgress: overall,
                        currentFile: fileName,
                        filesProcessed: processedFiles,
                        totalFiles: totalFiles,
                        currentStage: .copying,
                        speed: speed,
                        timeRemaining: timeRemaining,
                        elapsedTime: elapsedTime,
                        averageSpeed: speed,
                        peakSpeed: nil,
                        bytesProcessed: totalBytesProcessed,
                        totalBytes: estimatedTotalBytes,
                        stageProgress: nil,
                        reusedCopies: nil,
                        perDestinationTotals: perDestinationTotals,
                        perDestinationCompleted: perDestinationCompleted
                    ))
                },
                onError: { fileName, err in
                    let nsErr = err as NSError
                    SharedLogger.error("Copy error on dest #\(destIndex + 1): \(fileName) – \(nsErr.domain)(\(nsErr.code)): \(nsErr.localizedDescription)", category: .transfer)
                    processedFiles += 1
                    if destIndex < perDestinationCompleted.count { perDestinationCompleted[destIndex] += 1 }
                    let srcURL = operation.sourceURL.appendingPathComponent(fileName)
                    let dstURL = destFolder.appendingPathComponent(fileName)
                    let result = FileOperationResult(
                        sourceURL: srcURL,
                        destinationURL: dstURL,
                        success: false,
                        error: err,
                        fileSize: (try? fileSystem.getFileSize(for: srcURL)) ?? 0,
                        verificationResult: nil,
                        processingTime: 0
                    )
                    Task {
                        await resultStore.upsert(result)
                        onFileResult?(result)
                    }
                }
            )

            // Verification pass per file
            SharedLogger.info("🔎 Starting verify on destination \(destIndex + 1)/\(destinationCount): \(destFolder.lastPathComponent)", category: .transfer)
            // If pipelining is enabled, we skip the sequential verification pass for this destination
            if shouldPipelineVerify == false {
            // Stream over files again for verification without holding them in memory
            if let enumerator = FileManager.default.enumerator(
                at: operation.sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
            while let fileURL = enumerator.nextObject() as? URL {
                // Check for cancellation outside of autoreleasepool
                try Task.checkCancellation()
                try await waitIfPaused()
                // Keep heavy work scoped to an autoreleasepool to minimize transient memory
                if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile != true { continue }
                
                // Destination path must mirror the same relative tree used during copy
                let relativePath: String = {
                    let base = operation.sourceURL.path
                    let full = fileURL.path
                    if full.hasPrefix(base + "/") {
                        return String(full.dropFirst(base.count + 1))
                    } else {
                        return fileURL.lastPathComponent
                    }
                }()
                let destinationFileURL = destFolder.appendingPathComponent(relativePath)
                let fileStartTime = Date()
                
                do {
                    let sizeForVerify = (try? fileSystem.getFileSize(for: fileURL)) ?? 0
                    // Verify if requested
                    var verificationResult: VerificationResult? = nil
                    // Recompute timing for verification stage
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    let speed = elapsedTime > 0 ? Double(totalBytesProcessed) / elapsedTime : nil
                    let estimatedTotalBytes: Int64 = {
                        if let etb = operation.estimatedTotalBytes, etb > 0 { return etb }
                        if processedFiles > 0 {
                            let avg = totalBytesProcessed / Int64(processedFiles)
                            return Int64(totalFiles) * avg
                        }
                        return 50 * 1024 * 1024 * Int64(totalFiles)
                    }()
                    let timeRemaining = speed != nil && speed! > 0 ? Double(estimatedTotalBytes - totalBytesProcessed) / speed! : nil
                    if operation.verificationMode == .paranoid {
                        // Paranoid mode: Use byte-by-byte comparison
                        // Emit enhanced progress for verification phase (paranoid)
                        let verified = await verifyCounter.increment()
                        progressCallback(OperationProgress(
                            overallProgress: Double(processedFiles + verified) / Double(max(1, totalFiles * totalStageUnits)),
                            currentFile: fileURL.lastPathComponent,
                            filesProcessed: processedFiles,
                            totalFiles: totalFiles,
                            currentStage: .verifying,
                            speed: speed,
                            timeRemaining: timeRemaining,
                            elapsedTime: elapsedTime,
                            averageSpeed: speed,
                            peakSpeed: nil,
                            bytesProcessed: totalBytesProcessed,
                            totalBytes: estimatedTotalBytes,
                            stageProgress: Double(verified) / Double(max(1, totalFiles)),
                            reusedCopies: nil,
                            perDestinationTotals: perDestinationTotals,
                            perDestinationCompleted: perDestinationCompleted
                        ))
                        
                        let matches = try await checksumService.performByteComparison(
                            sourceURL: fileURL,
                            destinationURL: destinationFileURL,
                            progressCallback: nil as ChecksumService.ProgressCallback?
                        )
                        verificationResult = VerificationResult(
                            sourceChecksum: "byte-comparison",
                            destinationChecksum: "byte-comparison",
                            matches: matches,
                            checksumType: .sha256,
                            processingTime: Date().timeIntervalSince(fileStartTime),
                            fileSize: sizeForVerify
                        )
                    } else if operation.verificationMode.useChecksum {
                        // Standard/Thorough modes: Use checksum verification
                        // Emit enhanced progress for verification phase (checksum)
                        let verified = await verifyCounter.increment()
                        progressCallback(OperationProgress(
                            overallProgress: Double(processedFiles + verified) / Double(max(1, totalFiles * totalStageUnits)),
                            currentFile: fileURL.lastPathComponent,
                            filesProcessed: processedFiles,
                            totalFiles: totalFiles,
                            currentStage: .verifying,
                            speed: speed,
                            timeRemaining: timeRemaining,
                            elapsedTime: elapsedTime,
                            averageSpeed: speed,
                            peakSpeed: nil,
                            bytesProcessed: totalBytesProcessed,
                            totalBytes: estimatedTotalBytes,
                            stageProgress: Double(verified) / Double(max(1, totalFiles)),
                            reusedCopies: nil,
                            perDestinationTotals: perDestinationTotals,
                            perDestinationCompleted: perDestinationCompleted
                        ))
                        
                        if operation.verificationMode == .thorough {
                            // Compute all requested checksums and aggregate match state.
                            var combinedMatches = true
                            var primaryResult: VerificationResult?
                            var totalProcessing: TimeInterval = 0
                            for type in operation.verificationMode.checksumTypes {
                                let res = try await checksumService.verifyFileIntegrity(
                                    sourceURL: fileURL,
                                    destinationURL: destinationFileURL,
                                    type: type,
                                    progressCallback: nil
                                )
                                combinedMatches = combinedMatches && res.matches
                                totalProcessing += res.processingTime
                                if type == .sha256 { primaryResult = res }
                            }
                            if let base = primaryResult {
                                verificationResult = VerificationResult(
                                    sourceChecksum: base.sourceChecksum,
                                    destinationChecksum: base.destinationChecksum,
                                    matches: combinedMatches,
                                    checksumType: base.checksumType,
                                    processingTime: totalProcessing,
                                    fileSize: base.fileSize
                                )
                            } else {
                                // Fallback to first algorithm if SHA-256 wasn't included for any reason
                                let firstType = operation.verificationMode.checksumTypes.first ?? .sha256
                                verificationResult = try await checksumService.verifyFileIntegrity(
                                    sourceURL: fileURL,
                                    destinationURL: destinationFileURL,
                                    type: firstType,
                                    progressCallback: nil
                                )
                            }
                        } else {
                            let checksumType = operation.verificationMode.checksumTypes.first ?? .sha256
                            verificationResult = try await checksumService.verifyFileIntegrity(
                                sourceURL: fileURL,
                                destinationURL: destinationFileURL,
                                type: checksumType,
                                progressCallback: nil
                            )
                        }
                    }
                    // Quick mode (.quick): Skip verification entirely (verificationResult stays nil)
                    
                    let fileSize = sizeForVerify
                    let result = FileOperationResult(
                        sourceURL: fileURL,
                        destinationURL: destinationFileURL,
                        success: true,
                        error: nil,
                        fileSize: fileSize,
                        verificationResult: verificationResult,
                        processingTime: Date().timeIntervalSince(fileStartTime)
                    )
                    await resultStore.upsert(result)
                    onFileResult?(result)
                
                } catch {
                    let nsErr = error as NSError
                    SharedLogger.error("Verify error on dest #\(destIndex + 1): \(fileURL.lastPathComponent) – \(nsErr.domain)(\(nsErr.code)): \(nsErr.localizedDescription)", category: .transfer)
                    let result = FileOperationResult(
                        sourceURL: fileURL,
                        destinationURL: destinationFileURL,
                        success: false,
                        error: error,
                        fileSize: 0,
                        verificationResult: nil,
                        processingTime: Date().timeIntervalSince(fileStartTime)
                    )
                    await resultStore.upsert(result)
                    onFileResult?(result)
                }
                // processedFiles is incremented during copy callbacks
            } // end streaming enumeration
            }
            } // end non-pipelined verify

            SharedLogger.info("✅ Completed destination \(destIndex + 1)/\(destinationCount): \(destFolder.path)", category: .transfer)
        }
        
        // Wait for any in-flight pipelined verifications to complete
        for task in verifyTasks { await task.value }

        // Final progress update
        // Final progress update including total bytes
        let finalEstimatedTotalBytes: Int64 = {
            if let folderTotalSize = operation.estimatedTotalBytes, folderTotalSize > 0 {
                return folderTotalSize
            }
            if processedFiles > 0 {
                let averageBytesPerFile = totalBytesProcessed / Int64(processedFiles)
                return Int64(totalFiles) * averageBytesPerFile
            }
            return 50 * 1024 * 1024 * Int64(totalFiles)
        }()
        progressCallback(OperationProgress(
            overallProgress: 1.0,
            currentFile: nil,
            filesProcessed: totalFiles,
            totalFiles: totalFiles,
            currentStage: .completed,
            speed: nil,
            timeRemaining: 0,
            elapsedTime: Date().timeIntervalSince(startTime),
            averageSpeed: nil,
            peakSpeed: nil,
            bytesProcessed: totalBytesProcessed,
            totalBytes: finalEstimatedTotalBytes,
            stageProgress: nil
        ))
        
        let finalResults = await resultStore.snapshot()
        return FileOperation(
            sourceURL: operation.sourceURL,
            destinationURLs: operation.destinationURLs,
            startTime: operation.startTime,
            endTime: Date(),
            results: finalResults,
            verificationMode: operation.verificationMode,
            settings: operation.settings,
            estimatedTotalBytes: operation.estimatedTotalBytes
        )
    }
}
