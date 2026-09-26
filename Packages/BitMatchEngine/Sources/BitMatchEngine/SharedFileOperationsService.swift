// SharedFileOperationsService.swift - Platform-agnostic file operations
// Uses shared AsyncSemaphore from AsyncSemaphore.swift
import Foundation
import Synchronization

private struct FileResultKey: Hashable {
    let sourcePath: String
    let destinationPath: String

    init(sourceURL: URL, destinationURL: URL) {
        self.sourcePath = sourceURL.standardizedFileURL.path
        self.destinationPath = destinationURL.standardizedFileURL.path
    }
}

// Thread-safe accumulator for results coalescing (copy -> verified)
public actor ResultStore {
    public init() {}

    private var list: [FileOperationResult] = []
    private var indexByKey: [FileResultKey: Int] = [:]

    public func upsert(_ r: FileOperationResult) {
        let key = FileResultKey(sourceURL: r.sourceURL, destinationURL: r.destinationURL)
        if let idx = indexByKey[key] {
            list[idx] = r
        } else {
            indexByKey[key] = list.count
            list.append(r)
        }
    }
    public func snapshot() -> [FileOperationResult] { list }
}

public actor VerifyCounter {
    public init() {}

    private var value: Int = 0

    public func reset() {
        value = 0
    }

    public func increment() -> Int {
        value += 1
        return value
    }

    public func current() -> Int {
        value
    }
}

/// Thread-safe progress tracking for multi-destination copies (Bug 1 fix)
public actor DestinationProgress {
    private var completed: [Int]
    private let totals: [Int]

    public init(destinationCount: Int, perSourceFileCount: Int) {
        self.completed = Array(repeating: 0, count: destinationCount)
        self.totals = Array(repeating: perSourceFileCount, count: destinationCount)
    }

    public func increment(destIndex: Int) {
        guard destIndex < completed.count else { return }
        completed[destIndex] += 1
    }

    public func snapshot() -> (completed: [Int], totals: [Int]) {
        (completed, totals)
    }
}

/// Serialized progress state to avoid data races across concurrent copy/verify tasks.
public actor ProgressState {
    public init() {}

    private var processedFiles = 0
    private var totalBytesProcessed: Int64 = 0
    private var lastProgressCallbackTime = Date.distantPast
    private var lastCopyLogCount = 0

    public struct CopyUpdate: Sendable {
        public let processedFiles: Int
        public let totalBytesProcessed: Int64
        public let shouldEmitProgress: Bool
        public let shouldLog: Bool

        public init(processedFiles: Int, totalBytesProcessed: Int64, shouldEmitProgress: Bool, shouldLog: Bool) {
            self.processedFiles = processedFiles
            self.totalBytesProcessed = totalBytesProcessed
            self.shouldEmitProgress = shouldEmitProgress
            self.shouldLog = shouldLog
        }
    }

    public func recordCopy(fileSize: Int64, totalFiles: Int, now: Date, throttleInterval: TimeInterval) -> CopyUpdate {
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

    public func recordCopyError() -> (processedFiles: Int, totalBytesProcessed: Int64) {
        processedFiles += 1
        return (processedFiles, totalBytesProcessed)
    }

    public func shouldEmitVerify(now: Date, throttleInterval: TimeInterval, force: Bool) -> Bool {
        if force || now.timeIntervalSince(lastProgressCallbackTime) >= throttleInterval {
            lastProgressCallbackTime = now
            return true
        }
        return false
    }

    public func snapshot() -> (processedFiles: Int, totalBytesProcessed: Int64) {
        (processedFiles, totalBytesProcessed)
    }
}

/// Serialized storage for pipelined verification tasks.
public actor VerifyTaskStore {
    public init() {}

    private var tasks: [Task<Void, Never>] = []

    public func enqueue(_ task: Task<Void, Never>, maxQueued: Int) -> Task<Void, Never>? {
        tasks.append(task)
        if tasks.count >= max(1, maxQueued) {
            return tasks.removeFirst()
        }
        return nil
    }

    public func drain() -> [Task<Void, Never>] {
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
public final class ActiveOperationRegistry: Sendable {
    private struct State {
        var activeID: UUID?
        var task: Task<FileOperation, Error>?
        var cancellationRequested = false
    }

    private let state = Mutex(State())

    public init() {}

    public func reserve(_ id: UUID) -> Bool {
        state.withLock { state in
            guard state.activeID == nil else { return false }
            state = State(activeID: id)
            return true
        }
    }

    /// Attaches the run's task. A cancel that arrived before this still
    /// cancels it (I2); a task for a run that is not active is cancelled.
    public func attach(_ task: Task<FileOperation, Error>, to id: UUID) {
        let shouldCancel = state.withLock { state in
            guard state.activeID == id else { return true }
            state.task = task
            return state.cancellationRequested
        }
        if shouldCancel {
            task.cancel()
        }
    }

    public func requestCancellation() {
        let task = state.withLock { state -> Task<FileOperation, Error>? in
            guard state.activeID != nil else { return nil }
            state.cancellationRequested = true
            return state.task
        }
        task?.cancel()
    }

    public func clear(_ id: UUID) {
        state.withLock { state in
            guard state.activeID == id else { return }
            state = State()
        }
    }
}

public final class SharedFileOperationsService: FileOperationsService, Sendable {

    private let fileSystem: any FileAccess
    private let checksumService: any ChecksumService
    /// Test seam invoked with the raw destination URL immediately before that
    /// destination is pinned. It performs no filesystem work in production
    /// (nil); tests use it to block or fail destination setup deterministically.
    private let destinationSetupHook: (@Sendable (URL) throws -> Void)?
    /// Verify each file while later files copy (checksum modes only). The
    /// platform managers turn it off with the hidden `DisablePipelinedVerify`
    /// default; the engine itself reads no settings.
    private let pipelinedVerification: Bool
    private let activeOperations = ActiveOperationRegistry()
    private let pauseGate = PauseGate()
    private let verifyCounter = VerifyCounter()

    public init(
        fileSystem: any FileAccess,
        checksum: any ChecksumService,
        pipelinedVerification: Bool = true,
        destinationSetupHook: (@Sendable (URL) throws -> Void)? = nil
    ) {
        self.fileSystem = fileSystem
        self.checksumService = checksum
        self.pipelinedVerification = pipelinedVerification
        self.destinationSetupHook = destinationSetupHook
    }
    
    // MARK: - FileOperationsService Protocol Implementation
    
    public func performFileOperation(
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

        // A pause left over from an earlier run never holds this one (I5).
        pauseGate.resume()
        
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
        
        // The run's gate reaches every read below it, including the verify
        // tasks it starts, and nothing outside it (I9).
        let operationTask = Task { [pauseGate] in
            try await PauseGate.$current.withValue(pauseGate) {
                try await executeOperation(operation, progressCallback: progressCallback, onFileResult: onFileResult)
            }
        }
        activeOperations.attach(operationTask, to: operationID)

        return try await withTaskCancellationHandler {
            try await operationTask.value
        } onCancel: {
            operationTask.cancel()
        }
    }
    
    public func cancelOperation() {
        activeOperations.requestCancellation()
    }
    
    public func pauseOperation() async {
        pauseGate.pause()
    }

    public func resumeOperation() async {
        pauseGate.resume()
    }

    private func waitIfPaused() async throws {
        try await pauseGate.wait()
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
            speed: nil))

        await verifyCounter.reset()
        let pauseGate = self.pauseGate
        let didStartSourceScope = fileSystem.startAccessing(url: operation.sourceURL)
        var destinationScopes: [URL: Bool] = [:]
        for destinationURL in operation.destinationURLs {
            destinationScopes[destinationURL] = fileSystem.startAccessing(url: destinationURL)
        }
        defer {
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
        let manifestURLByRelativePath = Dictionary(
            sourceManifest.map { ($0.relativePath, $0.url) },
            uniquingKeysWith: { first, _ in first }
        )
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
        let totalFiles = perSourceFileCount * operation.destinationURLs.count
        SharedLogger.debug("Prep: source files=\(perSourceFileCount), destinations=\(operation.destinationURLs.count), planned total rows=\(totalFiles)", category: .transfer)
        let destinationCount = operation.destinationURLs.count
        let destProgress = DestinationProgress(destinationCount: destinationCount, perSourceFileCount: perSourceFileCount)
        let totalStageUnits = operation.verificationMode == .quick ? 1 : 2
        let progressState = ProgressState()
        
        // Free space was checked once, above, by SafetyValidator: the
        // measured source plus 1 GB, the rule Setup shows.

        // Step 3: Copy files to each destination
        let startTime = Date()
        // Perf 5: pipelined verification on by default for checksum/byte-compare modes; user can disable
        let shouldPipelineVerify = operation.verificationMode != .quick
            && pipelinedVerification
        // Perf 6: adaptive concurrency based on CPU count
        let verifyConcurrency = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        let verifySemaphore = AsyncSemaphore(count: shouldPipelineVerify ? verifyConcurrency : 0)
        let maxQueuedVerifyTasks = 200
        // Perf 2: time-based throttle on progress callbacks (500ms)
        let progressThrottleInterval: TimeInterval = 0.5
        
        let sourceFileURLs = sourceManifest.map(\.url)
        // Perf 7: adaptive copy worker count
        let copyWorkers = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

        // Collect each destination's resolved output root so per-destination
        // Handoff records are handled by the executor after verification finishes.
        var resolvedDestinations: [(raw: URL, root: URL)] = []

        for (destIndex, destinationURL) in operation.destinationURLs.enumerated() {
            // Pin the selected destination and every recipe component before
            // copying. Subsequent directory creation and publish are relative
            // to that descriptor, never a re-resolved pathname.
            let pinnedDestination: PinnedDestinationDirectory
            do {
                _ = try SafetyValidator.resolvedDestinationRootChecked(
                    source: operation.sourceURL,
                    destination: destinationURL,
                    settings: operation.settings
                )
                let rootComponents = SafetyValidator.destinationRootComponents(
                    source: operation.sourceURL,
                    settings: operation.settings
                )
                // No pathname-based write happens here: PinnedDestinationDirectory.open
                // creates every recipe component descriptor-relative with O_NOFOLLOW.
                try Task.checkCancellation()
                try destinationSetupHook?(destinationURL)
                pinnedDestination = try PinnedDestinationDirectory.open(
                    destination: destinationURL,
                    rootComponents: rootComponents
                )
            } catch let error as FileOperationError {
                // A safety-policy rejection (e.g. a symlink substituted into
                // the destination path) is a fail-closed signal, not a
                // per-destination access problem -- surface it as before so
                // the whole operation aborts rather than silently treating
                // the attack as "this destination is unavailable".
                throw error
            } catch is CancellationError {
                // Cancellation is never "this destination failed": it must not
                // fabricate failure rows or move on to the next destination.
                throw CancellationError()
            } catch {
                // A single inaccessible destination (e.g. permission denied,
                // volume ejected) must not abort the whole multi-destination
                // transfer. Report every planned file for this destination as
                // failed and move on to the next one.
                SharedLogger.error("Unable to open destination #\(destIndex + 1): \(error.localizedDescription)", category: .transfer)
                let fallbackRoot = SafetyValidator.resolvedDestinationRoot(
                    source: operation.sourceURL,
                    destination: destinationURL,
                    settings: operation.settings
                )
                for entry in sourceManifest {
                    let result = FileOperationResult(
                        sourceURL: entry.url,
                        destinationURL: fallbackRoot.appendingPathComponent(entry.relativePath),
                        success: false,
                        error: error,
                        fileSize: 0,
                        verificationResult: nil,
                        processingTime: 0
                    )
                    _ = await progressState.recordCopyError()
                    await destProgress.increment(destIndex: destIndex)
                    await resultStore.upsert(result)
                    await onFileResult?(result)
                }
                continue
            }
            let destFolder = pinnedDestination.logicalRootURL
            resolvedDestinations.append((raw: destinationURL, root: destFolder))

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
                checksumService: self.checksumService,
                preEnumeratedFiles: sourceFileURLs,
                pauseCheck: {
                    try await pauseGate.wait()
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
                    // Key result rows by the manifest's URL so copy and verify rows
                    // for one file share an identity even when the enumerator
                    // reports the source through a different path alias.
                    let srcURL = manifestURLByRelativePath[relativePath]
                        ?? operation.sourceURL.appendingPathComponent(relativePath)
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
                            // Bug 7 fix: use withSemaphore to guarantee permit release on cancel/throw.
                            // Only acquisition can throw here (CancellationError while
                            // queued): every operation outcome is recorded inside,
                            // so `try?` discards exactly the no-permit case.
                            _ = try? await withSemaphore(verifySemaphore) {
                                do {
                                    try Task.checkCancellation()
                                    try await self.waitIfPaused()
                                    let verificationResult = try await FileCopyService.verifyPinnedDestinationFile(
                                        source: srcURL,
                                        pinnedRoot: pinnedDestination,
                                        relativePath: relativePath,
                                        verificationMode: mode,
                                        checksumService: self.checksumService
                                    )
                                    let verified = FileOperationResult(
                                        sourceURL: srcURL,
                                        destinationURL: dstURL,
                                        success: verificationResult.matches,
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
                                        let overall = Double(metrics.processedFiles + verifiedCount) / Double(max(1, totalFiles * totalStageUnits))
                                        let snap = await destProgress.snapshot()
                                        progressCallback(OperationProgress(
                                            overallProgress: overall,
                                            currentFile: srcURL.lastPathComponent,
                                            filesProcessed: metrics.processedFiles,
                                            totalFiles: totalFiles,
                                            currentStage: .verifying,
                                            speed: speed,
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
                        let overall = Double(copyUpdate.processedFiles) / Double(max(1, totalFiles * totalStageUnits))
                        let copySnap = await destProgress.snapshot()
                        progressCallback(OperationProgress(
                            overallProgress: overall,
                            currentFile: fileName,
                            filesProcessed: copyUpdate.processedFiles,
                            totalFiles: totalFiles,
                            currentStage: .copying,
                            speed: speed,
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
                            // Verification reads the destination through the pinned
                            // directory descriptor; this URL is report metadata only.
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
                            let verified = await verifyCounter.increment()
                            let shouldEmit = await progressState.shouldEmitVerify(
                                now: Date(),
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
                            let verificationResult = try await FileCopyService.verifyPinnedDestinationFile(
                                source: fileURL,
                                pinnedRoot: pinnedDestination,
                                relativePath: relativePath,
                                verificationMode: operation.verificationMode,
                                checksumService: self.checksumService
                            )
                            
                            let fileSize = sizeForVerify
                            let result = FileOperationResult(
                                sourceURL: fileURL,
                                destinationURL: destinationFileURL,
                                success: verificationResult.matches,
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

        // The executor writes optional ASC MHL handoff records after authoritative verification.

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
