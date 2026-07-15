// SharedFileOperationsService.swift - Platform-agnostic file operations
// Uses shared AsyncSemaphore from AsyncSemaphore.swift
import Foundation

private struct FileResultKey: Hashable {
    let sourcePath: String
    let destinationPath: String

    init(sourceURL: URL, destinationURL: URL) {
        self.sourcePath = sourceURL.standardizedFileURL.path
        self.destinationPath = destinationURL.standardizedFileURL.path
    }
}

// Thread-safe accumulator for results coalescing (copy -> verified)
actor ResultStore {
    private var list: [FileOperationResult] = []
    private var indexByKey: [FileResultKey: Int] = [:]

    func upsert(_ r: FileOperationResult) {
        let key = FileResultKey(sourceURL: r.sourceURL, destinationURL: r.destinationURL)
        if let idx = indexByKey[key] {
            list[idx] = r
        } else {
            indexByKey[key] = list.count
            list.append(r)
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

/// Thread-safe progress tracking for multi-destination copies (Bug 1 fix)
actor DestinationProgress {
    private var completed: [Int]
    private let totals: [Int]

    init(destinationCount: Int, perSourceFileCount: Int) {
        self.completed = Array(repeating: 0, count: destinationCount)
        self.totals = Array(repeating: perSourceFileCount, count: destinationCount)
    }

    func increment(destIndex: Int) {
        guard destIndex < completed.count else { return }
        completed[destIndex] += 1
    }

    func snapshot() -> (completed: [Int], totals: [Int]) {
        (completed, totals)
    }
}

/// Serialized progress state to avoid data races across concurrent copy/verify tasks.
actor ProgressState {
    private var processedFiles = 0
    private var totalBytesProcessed: Int64 = 0
    private var lastProgressCallbackTime = Date.distantPast
    private var lastCopyLogCount = 0

    struct CopyUpdate {
        let processedFiles: Int
        let totalBytesProcessed: Int64
        let shouldEmitProgress: Bool
        let shouldLog: Bool
    }

    func recordCopy(fileSize: Int64, totalFiles: Int, now: Date, throttleInterval: TimeInterval) -> CopyUpdate {
        processedFiles += 1
        totalBytesProcessed += max(0, fileSize)

        let shouldLog = processedFiles - lastCopyLogCount >= 25 || processedFiles == totalFiles
        if shouldLog {
            lastCopyLogCount = processedFiles
        }

        let isFirstOrLast = processedFiles <= 1 || processedFiles >= totalFiles
        let shouldEmitProgress = isFirstOrLast || now.timeIntervalSince(lastProgressCallbackTime) >= throttleInterval
        if shouldEmitProgress {
            lastProgressCallbackTime = now
        }

        return CopyUpdate(
            processedFiles: processedFiles,
            totalBytesProcessed: totalBytesProcessed,
            shouldEmitProgress: shouldEmitProgress,
            shouldLog: shouldLog
        )
    }

    func recordCopyError() -> (processedFiles: Int, totalBytesProcessed: Int64) {
        processedFiles += 1
        return (processedFiles, totalBytesProcessed)
    }

    func shouldEmitVerify(now: Date, throttleInterval: TimeInterval, force: Bool) -> Bool {
        if force || now.timeIntervalSince(lastProgressCallbackTime) >= throttleInterval {
            lastProgressCallbackTime = now
            return true
        }
        return false
    }

    func snapshot() -> (processedFiles: Int, totalBytesProcessed: Int64) {
        (processedFiles, totalBytesProcessed)
    }
}

/// Serialized storage for pipelined verification tasks.
actor VerifyTaskStore {
    private var tasks: [Task<Void, Never>] = []

    func enqueue(_ task: Task<Void, Never>, maxQueued: Int) -> Task<Void, Never>? {
        tasks.append(task)
        if tasks.count >= max(1, maxQueued) {
            return tasks.removeFirst()
        }
        return nil
    }

    func drain() -> [Task<Void, Never>] {
        let pending = tasks
        tasks.removeAll()
        return pending
    }
}

/// Safe multiplication that returns Int64.max on overflow (Bug 6 fix)
private func safeMultiply(_ a: Int64, _ b: Int64) -> Int64 {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    return overflow ? Int64.max : result
}

/// Owns the single operation admitted by a service instance.
/// Cancellation never releases the slot; only the matching operation's exit does.
private final class ActiveOperationRegistry: @unchecked Sendable {
    private struct Entry {
        var task: Task<FileOperation, Error>?
        var cancellationRequested = false
    }

    private let lock = NSLock()
    private var activeID: UUID?
    private var entries: [UUID: Entry] = [:]

    func reserve(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeID == nil else { return false }
        activeID = id
        entries[id] = Entry()
        return true
    }

    func attach(_ task: Task<FileOperation, Error>, to id: UUID) {
        lock.lock()
        guard activeID == id, var entry = entries[id] else {
            lock.unlock()
            task.cancel()
            return
        }
        entry.task = task
        entries[id] = entry
        let shouldCancel = entry.cancellationRequested
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func requestCancellation() {
        lock.lock()
        guard let id = activeID, var entry = entries[id] else {
            lock.unlock()
            return
        }
        entry.cancellationRequested = true
        entries[id] = entry
        let task = entry.task
        lock.unlock()

        task?.cancel()
    }

    func clear(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard activeID == id else { return }
        entries[id] = nil
        activeID = nil
    }
}

class SharedFileOperationsService: FileOperationsService {
    typealias ProgressCallback = (OperationProgress) -> Void

    private let fileSystem: FileSystemService
    private let checksumService: any ChecksumService
    private let activeOperations = ActiveOperationRegistry()
    private let pauseState = PauseState()
    private let verifyCounter = VerifyCounter()

    /// Thread-safe pause state management
    private actor PauseState {
        private var paused = false
        func isPaused() -> Bool { paused }
        func pause() { paused = true }
        func resume() { paused = false }

        func waitIfPaused() async throws {
            while paused && !Task.isCancelled {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
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
        onFileResult: FileResultCallback?
    ) async throws -> FileOperation {
        let operationID = UUID()
        guard activeOperations.reserve(operationID) else {
            throw FileOperationError.operationAlreadyInProgress
        }
        defer { activeOperations.clear(operationID) }

        await pauseState.resume()
        
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
        activeOperations.attach(operationTask, to: operationID)

        return try await withTaskCancellationHandler {
            try await operationTask.value
        } onCancel: {
            operationTask.cancel()
        }
    }
    
    func cancelOperation() {
        activeOperations.requestCancellation()
    }
    
    func pauseOperation() async {
        await pauseState.pause()
    }

    func resumeOperation() async {
        await pauseState.resume()
    }

    private func waitIfPaused() async throws {
        try await pauseState.waitIfPaused()
    }

    private func finishVerificationTasks(
        in store: VerifyTaskStore,
        cancelling: Bool
    ) async {
        let tasks = await store.drain()
        if cancelling {
            tasks.forEach { $0.cancel() }
        }
        await withTaskCancellationHandler {
            for task in tasks {
                await task.value
            }
        } onCancel: {
            tasks.forEach { $0.cancel() }
        }
    }
    
    // MARK: - Private Implementation
    
    private func executeOperation(
        _ operation: FileOperation,
        progressCallback: @escaping ProgressCallback,
        onFileResult: FileResultCallback?
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
        let pauseState = self.pauseState
        SharedChecksumService.pauseCheck = {
            try await pauseState.waitIfPaused()
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

        let verifyTaskStore = VerifyTaskStore()
        do {
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

        // Step 2: Build one fail-closed source manifest before safety validation.
        SharedLogger.debug("Prep: enumerating source manifest at \(operation.sourceURL.path)", category: .transfer)
        let sourceManifest = try FileTreeEnumerator.enumerateRegularFiles(base: operation.sourceURL)
        let manifestBytes = try sourceManifest.reduce(Int64(0)) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(max(0, entry.size))
            guard !overflow else {
                throw FileOperationError.unsafeOperation("Source size exceeds the supported range")
            }
            return sum
        }

        try SafetyValidator.validateResolvedDestinationRoots(
            source: operation.sourceURL,
            destinations: operation.destinationURLs,
            settings: operation.settings
        )

        try await SafetyValidator.performSafetyChecks(
            source: operation.sourceURL,
            destinations: operation.destinationURLs,
            sourceSizeBytes: manifestBytes
        )

        let perSourceFileCount = sourceManifest.count
        let totalSizeBytes = operation.estimatedTotalBytes ?? manifestBytes
        let totalFiles = perSourceFileCount * operation.destinationURLs.count
        SharedLogger.debug("Prep: source files=\(perSourceFileCount), destinations=\(operation.destinationURLs.count), planned total rows=\(totalFiles)", category: .transfer)
        let destinationCount = operation.destinationURLs.count
        let destProgress = DestinationProgress(destinationCount: destinationCount, perSourceFileCount: perSourceFileCount)
        let totalStageUnits = operation.verificationMode == .quick ? 1 : 2
        let progressState = ProgressState()
        
        // Step 2a: Validate sufficient storage space
        for (index, destinationURL) in operation.destinationURLs.enumerated() {
            let available = fileSystem.freeSpace(at: destinationURL)
            SharedLogger.debug("Storage check dest #\(index+1): need \(totalSizeBytes), have \(available)", category: .transfer)
            
            // Add 100MB buffer for overhead/filesystem structures
            let requiredSizeBytes = try SafetyValidator.checkedRequiredSpace(
                sourceBytes: totalSizeBytes,
                headroomBytes: 100 * 1024 * 1024
            )
            if available < requiredSizeBytes {
                throw BitMatchError.insufficientStorage(totalSizeBytes, available)
            }
        }

        // Step 3: Copy files to each destination
        let startTime = Date()
        // Perf 5: pipelined verification on by default for checksum/byte-compare modes; user can disable
        let shouldPipelineVerify = operation.verificationMode != .quick
            && !UserDefaults.standard.bool(forKey: "DisablePipelinedVerify")
        // Perf 6: adaptive concurrency based on CPU count
        let verifyConcurrency = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        let verifySemaphore = AsyncSemaphore(count: shouldPipelineVerify ? verifyConcurrency : 0)
        let maxQueuedVerifyTasks = 200
        // Perf 2: time-based throttle on progress callbacks (500ms)
        let progressThrottleInterval: TimeInterval = 0.5
        
        let sourceFileURLs = sourceManifest.map(\.url)
        // Perf 7: adaptive copy worker count
        let copyWorkers = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

        for (destIndex, destinationURL) in operation.destinationURLs.enumerated() {
            // Pin the selected destination and every recipe component before
            // copying. Subsequent directory creation and publish are relative
            // to that descriptor, never a re-resolved pathname.
            let checkedDestinationFolder = try SafetyValidator.resolvedDestinationRootChecked(
                source: operation.sourceURL,
                destination: destinationURL,
                settings: operation.settings
            )
            let rootComponents: [String]
            if let configuredComponents = operation.settings.destinationPathComponents {
                rootComponents = configuredComponents.map(CameraLabelSettings.sanitizePathComponent)
            } else {
                rootComponents = [checkedDestinationFolder.lastPathComponent]
            }
            let pinnedDestination = try PinnedDestinationDirectory.open(
                destination: destinationURL,
                rootComponents: rootComponents
            )
            let destFolder = pinnedDestination.logicalRootURL

            SharedLogger.info("➡️ Starting destination \(destIndex + 1)/\(destinationCount): \(destFolder.path)", category: .transfer)
            do {
                let snap = await destProgress.snapshot()
                if destIndex < snap.totals.count && destIndex < snap.completed.count {
                    SharedLogger.debug("   Resume seed on destination: \(snap.completed[destIndex])/\(snap.totals[destIndex]) files already present", category: .transfer)
                }
            }

            // Copy to this destination using atomic writes and resume-aware skip
            SharedLogger.info("→ Begin copy to dest #\(destIndex + 1)/\(destinationCount): \(destFolder.path)", category: .transfer)
            try await FileCopyService.copyAllSafely(
                from: operation.sourceURL,
                toPinnedRoot: pinnedDestination,
                verificationMode: operation.verificationMode,
                workers: copyWorkers,
                preEnumeratedFiles: sourceFileURLs,
                pauseCheck: {
                    try await pauseState.waitIfPaused()
                },
                onProgress: { fileName, fileSize in
                    let copyUpdate = await progressState.recordCopy(
                        fileSize: fileSize,
                        totalFiles: totalFiles,
                        now: Date(),
                        throttleInterval: progressThrottleInterval
                    )
                    await destProgress.increment(destIndex: destIndex)
                    if copyUpdate.shouldLog {
                        let formatted = ByteCountFormatter.string(fromByteCount: copyUpdate.totalBytesProcessed, countStyle: .file)
                        SharedLogger.debug("Copy progress: files=\(copyUpdate.processedFiles)/\(totalFiles) bytes=\(formatted)", category: .transfer)
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
                    await resultStore.upsert(copyResult)
                    await onFileResult?(copyResult)

                    if shouldPipelineVerify {
                        let mode = operation.verificationMode
                        let task = Task { [verifySemaphore] in
                            // Bug 7 fix: use withSemaphore to guarantee permit release on cancel/throw
                            await withSemaphore(verifySemaphore) {
                                do {
                                    try Task.checkCancellation()
                                    try await self.waitIfPaused()
                                    var verificationResult: VerificationResult?
                                    if mode == .paranoid {
                                        let matches = try await self.checksumService.performByteComparison(
                                            sourceURL: srcURL,
                                            destinationURL: dstURL,
                                            progressCallback: nil
                                        )
                                        verificationResult = VerificationResult(
                                            sourceChecksum: "byte-comparison",
                                            destinationChecksum: "byte-comparison",
                                            matches: matches,
                                            checksumType: .sha256,
                                            processingTime: 0,
                                            fileSize: max(0, fileSize)
                                        )
                                    } else if mode == .thorough {
                                        var combinedMatches = true
                                        var primaryResult: VerificationResult?
                                        var totalProcessing: TimeInterval = 0
                                        for type in mode.checksumTypes {
                                            let res = try await self.checksumService.verifyFileIntegrity(
                                                sourceURL: srcURL,
                                                destinationURL: dstURL,
                                                type: type,
                                                useCache: false,
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
                                                useCache: false,
                                                progressCallback: nil
                                            )
                                        }
                                    } else if mode.useChecksum {
                                        let t = mode.checksumTypes.first ?? .sha256
                                        verificationResult = try await self.checksumService.verifyFileIntegrity(
                                            sourceURL: srcURL,
                                            destinationURL: dstURL,
                                            type: t,
                                            useCache: false,
                                            progressCallback: nil
                                        )
                                    }
                                    let verified = FileOperationResult(
                                        sourceURL: srcURL,
                                        destinationURL: dstURL,
                                        success: verificationResult?.matches ?? true,
                                        error: nil,
                                        fileSize: max(0, fileSize),
                                        verificationResult: verificationResult,
                                        processingTime: 0
                                    )
                                    let verifiedCount = await self.verifyCounter.increment()
                                    // Perf 2: throttle pipelined verify progress callbacks
                                    let now = Date()
                                    let isLast = verifiedCount >= totalFiles
                                    let shouldEmitVerify = await progressState.shouldEmitVerify(
                                        now: now,
                                        throttleInterval: progressThrottleInterval,
                                        force: isLast
                                    )
                                    if shouldEmitVerify {
                                        let metrics = await progressState.snapshot()
                                        let elapsedTime = now.timeIntervalSince(startTime)
                                        let speed = elapsedTime > 0 ? Double(metrics.totalBytesProcessed) / elapsedTime : nil
                                        let estimatedTotalBytes: Int64 = {
                                            if let etb = operation.estimatedTotalBytes, etb > 0 { return etb }
                                            if metrics.processedFiles > 0 {
                                                let avg = metrics.totalBytesProcessed / Int64(metrics.processedFiles)
                                                return safeMultiply(Int64(totalFiles), avg)
                                            }
                                            return safeMultiply(50 * 1024 * 1024, Int64(totalFiles))
                                        }()
                                        let timeRemaining = speed != nil && speed! > 0 ? Double(estimatedTotalBytes - metrics.totalBytesProcessed) / speed! : nil
                                        let overall = Double(metrics.processedFiles + verifiedCount) / Double(max(1, totalFiles * totalStageUnits))
                                        let snap = await destProgress.snapshot()
                                        progressCallback(OperationProgress(
                                            overallProgress: overall,
                                            currentFile: srcURL.lastPathComponent,
                                            filesProcessed: metrics.processedFiles,
                                            totalFiles: totalFiles,
                                            currentStage: .verifying,
                                            speed: speed,
                                            timeRemaining: timeRemaining,
                                            elapsedTime: elapsedTime,
                                            averageSpeed: speed,
                                            peakSpeed: nil,
                                            bytesProcessed: metrics.totalBytesProcessed,
                                            totalBytes: estimatedTotalBytes,
                                            stageProgress: Double(verifiedCount) / Double(max(1, totalFiles)),
                                            reusedCopies: nil,
                                            perDestinationTotals: snap.totals,
                                            perDestinationCompleted: snap.completed
                                        ))
                                    }
                                    await resultStore.upsert(verified)
                                    await onFileResult?(verified)
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
                                    await onFileResult?(failure)
                                }
                            }
                        }
                        if let next = await verifyTaskStore.enqueue(task, maxQueued: maxQueuedVerifyTasks) {
                            await withTaskCancellationHandler {
                                await next.value
                            } onCancel: {
                                next.cancel()
                            }
                        }
                    }

                    if copyUpdate.shouldEmitProgress {
                        let now = Date()
                        let elapsedTime = now.timeIntervalSince(startTime)
                        let speed = elapsedTime > 0 ? Double(copyUpdate.totalBytesProcessed) / elapsedTime : nil
                        // Bug 6 fix: safe multiplication to prevent overflow
                        let estimatedTotalBytes: Int64 = {
                            if let etb = operation.estimatedTotalBytes, etb > 0 { return etb }
                            if copyUpdate.processedFiles > 0 {
                                let avg = copyUpdate.totalBytesProcessed / Int64(copyUpdate.processedFiles)
                                return safeMultiply(Int64(totalFiles), avg)
                            }
                            return safeMultiply(50 * 1024 * 1024, Int64(totalFiles))
                        }()
                        let timeRemaining = speed != nil && speed! > 0 ? Double(estimatedTotalBytes - copyUpdate.totalBytesProcessed) / speed! : nil
                        let overall = Double(copyUpdate.processedFiles) / Double(max(1, totalFiles * totalStageUnits))
                        let copySnap = await destProgress.snapshot()
                        progressCallback(OperationProgress(
                            overallProgress: overall,
                            currentFile: fileName,
                            filesProcessed: copyUpdate.processedFiles,
                            totalFiles: totalFiles,
                            currentStage: .copying,
                            speed: speed,
                            timeRemaining: timeRemaining,
                            elapsedTime: elapsedTime,
                            averageSpeed: speed,
                            peakSpeed: nil,
                            bytesProcessed: copyUpdate.totalBytesProcessed,
                            totalBytes: estimatedTotalBytes,
                            stageProgress: nil,
                            reusedCopies: nil,
                            perDestinationTotals: copySnap.totals,
                            perDestinationCompleted: copySnap.completed
                        ))
                    }
                },
                onError: { fileName, err in
                    let nsErr = err as NSError
                    SharedLogger.error("Copy error on dest #\(destIndex + 1): \(fileName) – \(nsErr.domain)(\(nsErr.code)): \(nsErr.localizedDescription)", category: .transfer)
                    let srcURL = operation.sourceURL.appendingPathComponent(fileName)
                    let dstURL = destFolder.appendingPathComponent(fileName)
                    let result = FileOperationResult(
                        sourceURL: srcURL,
                        destinationURL: dstURL,
                        success: false,
                        error: err,
                        fileSize: (try? self.fileSystem.getFileSize(for: srcURL)) ?? 0,
                        verificationResult: nil,
                        processingTime: 0
                    )
                    _ = await progressState.recordCopyError()
                    await destProgress.increment(destIndex: destIndex)
                    await resultStore.upsert(result)
                    await onFileResult?(result)
                }
            )

            // Verification pass per file
            SharedLogger.info("🔎 Starting verify on destination \(destIndex + 1)/\(destinationCount): \(destFolder.lastPathComponent)", category: .transfer)
            // If pipelining is enabled, we skip the sequential verification pass for this destination
            if operation.verificationMode != .quick && shouldPipelineVerify == false {
                // Perf 1: reuse the source manifest instead of re-enumerating filesystem
                for entry in sourceManifest {
                        try Task.checkCancellation()
                        try await waitIfPaused()
                        let fileURL = entry.url
                        let relativePath = entry.relativePath
                        let destinationFileURL = destFolder.appendingPathComponent(relativePath)
                        let fileStartTime = Date()
                        
                        do {
                            let sizeForVerify = max(0, entry.size)
                            // Verify if requested
                            var verificationResult: VerificationResult? = nil
                            // Recompute timing for verification stage
                            let elapsedTime = Date().timeIntervalSince(startTime)
                            let metrics = await progressState.snapshot()
                            let speed = elapsedTime > 0 ? Double(metrics.totalBytesProcessed) / elapsedTime : nil
                            // Bug 6 fix: safe multiplication to prevent overflow
                            let estimatedTotalBytes: Int64 = {
                                if let etb = operation.estimatedTotalBytes, etb > 0 { return etb }
                                if metrics.processedFiles > 0 {
                                    let avg = metrics.totalBytesProcessed / Int64(metrics.processedFiles)
                                    return safeMultiply(Int64(totalFiles), avg)
                                }
                                return safeMultiply(50 * 1024 * 1024, Int64(totalFiles))
                            }()
                            let timeRemaining = speed != nil && speed! > 0 ? Double(estimatedTotalBytes - metrics.totalBytesProcessed) / speed! : nil
                            if operation.verificationMode == .paranoid {
                                // Paranoid mode: Use byte-by-byte comparison
                                let verified = await verifyCounter.increment()
                                // Perf 2: throttle sequential verify progress callbacks
                                let verifyNow = Date()
                                let shouldEmit = await progressState.shouldEmitVerify(
                                    now: verifyNow,
                                    throttleInterval: progressThrottleInterval,
                                    force: verified >= totalFiles
                                )
                                if shouldEmit {
                                    let latest = await progressState.snapshot()
                                    let verifySnap = await destProgress.snapshot()
                                    progressCallback(OperationProgress(
                                        overallProgress: Double(latest.processedFiles + verified) / Double(max(1, totalFiles * totalStageUnits)),
                                        currentFile: fileURL.lastPathComponent,
                                        filesProcessed: latest.processedFiles,
                                        totalFiles: totalFiles,
                                        currentStage: .verifying,
                                        speed: speed,
                                        timeRemaining: timeRemaining,
                                        elapsedTime: elapsedTime,
                                        averageSpeed: speed,
                                        peakSpeed: nil,
                                        bytesProcessed: latest.totalBytesProcessed,
                                        totalBytes: estimatedTotalBytes,
                                        stageProgress: Double(verified) / Double(max(1, totalFiles)),
                                        reusedCopies: nil,
                                        perDestinationTotals: verifySnap.totals,
                                        perDestinationCompleted: verifySnap.completed
                                    ))
                                }
                                
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
                                let verified = await verifyCounter.increment()
                                // Perf 2: throttle sequential verify progress callbacks
                                let verifyNow2 = Date()
                                let shouldEmit = await progressState.shouldEmitVerify(
                                    now: verifyNow2,
                                    throttleInterval: progressThrottleInterval,
                                    force: verified >= totalFiles
                                )
                                if shouldEmit {
                                    let latest = await progressState.snapshot()
                                    let verifySnap = await destProgress.snapshot()
                                    progressCallback(OperationProgress(
                                        overallProgress: Double(latest.processedFiles + verified) / Double(max(1, totalFiles * totalStageUnits)),
                                        currentFile: fileURL.lastPathComponent,
                                        filesProcessed: latest.processedFiles,
                                        totalFiles: totalFiles,
                                        currentStage: .verifying,
                                        speed: speed,
                                        timeRemaining: timeRemaining,
                                        elapsedTime: elapsedTime,
                                        averageSpeed: speed,
                                        peakSpeed: nil,
                                        bytesProcessed: latest.totalBytesProcessed,
                                        totalBytes: estimatedTotalBytes,
                                        stageProgress: Double(verified) / Double(max(1, totalFiles)),
                                        reusedCopies: nil,
                                        perDestinationTotals: verifySnap.totals,
                                        perDestinationCompleted: verifySnap.completed
                                    ))
                                }

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
                                            useCache: false,
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
                                            useCache: false,
                                            progressCallback: nil
                                        )
                                    }
                                } else {
                                    let checksumType = operation.verificationMode.checksumTypes.first ?? .sha256
                                    verificationResult = try await checksumService.verifyFileIntegrity(
                                        sourceURL: fileURL,
                                        destinationURL: destinationFileURL,
                                        type: checksumType,
                                        useCache: false,
                                        progressCallback: nil
                                    )
                                }
                            }
                            
                            let fileSize = sizeForVerify
                            let result = FileOperationResult(
                                sourceURL: fileURL,
                                destinationURL: destinationFileURL,
                                success: verificationResult?.matches ?? true,
                                error: nil,
                                fileSize: fileSize,
                                verificationResult: verificationResult,
                                processingTime: Date().timeIntervalSince(fileStartTime)
                            )
                            await resultStore.upsert(result)
                            await onFileResult?(result)
                        
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
                            await onFileResult?(result)
                        }
                        // processedFiles is incremented during copy callbacks
                } // end file iteration
            } // end non-pipelined verify

            SharedLogger.info("✅ Completed destination \(destIndex + 1)/\(destinationCount): \(destFolder.path)", category: .transfer)
        }
        
        // Wait for any in-flight pipelined verifications to complete.
        await finishVerificationTasks(in: verifyTaskStore, cancelling: false)
        try Task.checkCancellation()

        let finalMetrics = await progressState.snapshot()

        // Final progress update including total bytes
        let finalEstimatedTotalBytes: Int64 = {
            if let folderTotalSize = operation.estimatedTotalBytes, folderTotalSize > 0 {
                return folderTotalSize
            }
            if finalMetrics.processedFiles > 0 {
                let averageBytesPerFile = finalMetrics.totalBytesProcessed / Int64(finalMetrics.processedFiles)
                return safeMultiply(Int64(totalFiles), averageBytesPerFile)
            }
            return safeMultiply(50 * 1024 * 1024, Int64(totalFiles))
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
            bytesProcessed: finalMetrics.totalBytesProcessed,
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
        } catch {
            await finishVerificationTasks(in: verifyTaskStore, cancelling: true)
            throw error
        }
    }
}
