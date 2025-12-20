// Core/Services/ComparisonOperationService.swift
import Foundation

/// Service for handling file comparison operations
final class ComparisonOperationService {
    
    // MARK: - Comparison Operations
    
    static func performComparison(
        left: URL,
        right: URL,
        verificationMode: VerificationMode,
        progressViewModel: ProgressViewModel,
        onProgress: @escaping ([ResultRow]) -> Void,
        onComplete: @escaping () -> Void,
        shouldGenerateMHL: Bool,
        mhlCollector: MHLOperationService.MHLCollectorActor?
    ) async throws {
        
        // Always perform real comparison in production testing
        
        // Count files for progress tracking
        let totalFiles = try await countFilesInDirectory(at: left)
        await MainActor.run {
            progressViewModel.setFileCountTotal(totalFiles)
        }
        
        // Limit verification concurrency to keep memory footprint predictable
        let workers = min(2, ProcessInfo.processInfo.activeProcessorCount)
        let needsMHL = shouldGenerateMHL
        
        // Process comparisons concurrently without materializing the full file list in memory
        try await withThrowingTaskGroup(of: ResultRow.self) { group in
            let semaphore = AsyncSemaphore(count: workers)
            // Batch results to reduce UI churn and memory pressure
            var batch: [ResultRow] = []
            batch.reserveCapacity(50)
            
            let fm = FileManager.default
            let enumKeys: [URLResourceKey] = [.isRegularFileKey]
            let maxInFlightTasks = max(128, workers * 32) // bound task graph to keep memory stable
            var inFlight = 0
            if let enumerator = fm.enumerator(at: left, includingPropertiesForKeys: enumKeys, options: [.skipsHiddenFiles]) {
                while let nextObj = enumerator.nextObject() as? URL {
                    do {
                        let isFile = try nextObj.resourceValues(forKeys: Set(enumKeys)).isRegularFile ?? false
                        if !isFile { continue }
                    } catch {
                        continue
                    }
                    let fileURL = nextObj
                    // Backpressure: if too many tasks are queued, drain one result before queuing more
                    if inFlight >= maxInFlightTasks {
                        if let row = try await group.next() { 
                            await OperationManager.checkPause()
                            await MainActor.run {
                                progressViewModel.incrementFileCompleted()
                                if row.status.contains("✅") || row.status.contains("Match") {
                                    progressViewModel.incrementMatch()
                                }
                            }
                            batch.append(row)
                            if batch.count >= 50 {
                                let toAdd = batch
                                batch.removeAll(keepingCapacity: true)
                                onProgress(toAdd)
                            }
                            inFlight -= 1
                        }
                    }
                    inFlight += 1
                    group.addTask {
                        await semaphore.wait()
                        let relativePath = String(fileURL.path.dropFirst(left.path.count + 1))
                        let counterpart = right.appendingPathComponent(relativePath)
                        
                        // Check if counterpart exists
                        guard FileManager.default.fileExists(atPath: counterpart.path) else {
                            await semaphore.signal()
                            return ResultRow(path: relativePath, status: "Missing in Destination", size: 0, checksum: nil, destination: nil)
                        }
                        
                        // Update progress: set current file name
                        await MainActor.run {
                            progressViewModel.setCurrentFile(fileURL.lastPathComponent)
                        }
                        
                        // Perform comparison
                        let result = await VerifyService.compare(leftURL: fileURL, rightURL: counterpart, relativePath: relativePath, verificationMode: verificationMode)
                        
                        // Collect checksum for MHL if needed
                        if needsMHL && (result.status.contains("✅") || result.status.contains("Match")) {
                            if let collector = mhlCollector {
                                do {
                                    try await MHLOperationService.collectMHLEntry(
                                        for: counterpart,
                                        algorithm: .sha256,
                                        collector: collector
                                    )
                                } catch {
                                    SharedLogger.warning("Failed to collect MHL entry: \(error)", category: .transfer)
                                }
                            }
                        }
                        await semaphore.signal()
                        return result
                    }
                }
            }
            // Process any remaining results in batches
            while let row = try await group.next() {
                await OperationManager.checkPause()
                
                await MainActor.run {
                    progressViewModel.incrementFileCompleted()
                    if row.status.contains("✅") || row.status.contains("Match") {
                        progressViewModel.incrementMatch()
                    }
                }
                
                batch.append(row)
                
                if batch.count >= 50 {
                    let toAdd = batch
                    batch.removeAll(keepingCapacity: true)
                    onProgress(toAdd)
                }
            }
            
            if !batch.isEmpty {
                onProgress(batch)
            }
        }
        
        // Check for extra files in destination
        try await FileDiffService.checkForExtraFiles(in: right, comparedTo: left, onProgress: onProgress)
        
        onComplete()
    }
    
    // MARK: - Copy and Verify Operations
    
    static func performCopyAndVerify(
        source: URL,
        destinations: [URL],
        verificationMode: VerificationMode,
        cameraLabelSettings: CameraLabelSettings,
        progressViewModel: ProgressViewModel,
        onProgress: @escaping ([ResultRow]) -> Void,
        onComplete: @escaping () -> Void,
        shouldGenerateMHL: Bool,
        mhlCollector: MHLOperationService.MHLCollectorActor?
    ) async throws {
        
        // Always perform real copy+verify in production testing
        
        // Safety checks
        try await performSafetyChecks(
            source: source,
            destinations: destinations
        )

        // Establish file counts for progress (copy phase) without holding full list
        let perDestFileCount = FileTreeEnumerator.countRegularFiles(base: source)
        let totalPlanned = perDestFileCount * max(1, destinations.count)
        await MainActor.run {
            progressViewModel.setFileCountTotal(totalPlanned)
            progressViewModel.configureDestinations(totalPerDestination: perDestFileCount, count: destinations.count)
            progressViewModel.setProgressMessage("Copying files…")
        }

        let destinationRootFor: (URL) -> URL = { destination in
            let baseName = source.lastPathComponent
            let labeledName = cameraLabelSettings.formattedFolderName(for: baseName)
            if cameraLabelSettings.groupByCamera {
                let raw = cameraLabelSettings.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let group = raw.isEmpty ? "Camera" : raw
                return destination.appendingPathComponent(group).appendingPathComponent(baseName)
            } else {
                let folderName = labeledName.isEmpty ? baseName : labeledName
                return destination.appendingPathComponent(folderName)
            }
        }

        // Pre-scan destinations to seed resume progress when files already exist and match size
        let alreadyPresentPerDestination: [Int] = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for destination in destinations {
                group.addTask {
                    let destRoot = destinationRootFor(destination)
                    return await PreScanService.countAlreadyPresentStreaming(sourceBase: source, destRoot: destRoot, verificationMode: verificationMode)
                }
            }
            var counts: [Int] = []
            for await c in group { counts.append(c) }
            return counts
        }
        let seeded = alreadyPresentPerDestination.reduce(0, +)
        if seeded > 0 {
            await MainActor.run {
                progressViewModel.incrementFileCompleted(seeded)
                // Bump per-destination counters to reflect seeded progress
                for (idx, c) in alreadyPresentPerDestination.enumerated() where c > 0 {
                    for _ in 0..<c { progressViewModel.incrementDestinationCompleted(index: idx) }
                }
                progressViewModel.setReusedFileCopies(seeded)
                // Only show the resume message if the reuse count is meaningful
                if seeded >= 3 {
                    progressViewModel.setProgressMessage("Resuming: \(seeded) already present…")
                }
            }
        }
        // Reuse enumerated file list via closure capture when copying to each destination
        
        // Diagnostics
        let resolvedDestinations = destinations.map { destinationRootFor($0).path }
        SharedLogger.info("Starting Copy & Verify - Source: \(source.path), Destinations: \(resolvedDestinations)", category: .transfer)

        // Copy files to all destinations.
        // Use conservative per-destination concurrency to keep memory stable under large file loads.
        let workers = 1
        await withThrowingTaskGroup(of: Void.self) { group in
            for (destIndex, destination) in destinations.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    // Create a top-level folder named after the source (e.g., card volume name)
                    let destRoot = destinationRootFor(destination)
                    do {
                        if !FileManager.default.fileExists(atPath: destRoot.path) {
                            try FileManager.default.createDirectory(at: destRoot, withIntermediateDirectories: true, attributes: nil)
                        }
                    } catch {
                        SharedLogger.error("Failed to prepare destination folder \(destRoot.path): \(error.localizedDescription)", category: .transfer)
                        throw error
                    }
                    SharedLogger.debug("Copying to: \(destRoot.path)", category: .transfer)

                    try await FileCopyService.copyAllSafely(
                        from: source,
                        toRoot: destRoot,
                        workers: workers,
                        preEnumeratedFiles: nil,
                        pauseCheck: nil,
                        onProgress: { fileName, fileSize in
                            // Dispatch to main actor without making this closure async
                            Task { @MainActor in
                                // Skip UI updates if cancelled to reduce warnings/spam
                                guard !Task.isCancelled else { return }
                                progressViewModel.setCurrentFile(fileName, size: fileSize)
                                progressViewModel.updateBytesProcessed(fileSize)
                                progressViewModel.incrementFileCompleted()
                                progressViewModel.incrementDestinationCompleted(index: destIndex)
                            }
                        },
                        onError: { fileName, error in
                            SharedLogger.error("Copy error for \(fileName): \(error.localizedDescription)", category: .transfer)
                        }
                    )
                }
            }
        }
        
        // Respect cancellation between copy and verify phases
        try Task.checkCancellation()
        
        // Verify copied files (compare against the per-card subfolder we created)
        for destination in destinations {
            let destRoot = destinationRootFor(destination)
            try Task.checkCancellation()
            try await performComparison(
                left: source,
                right: destRoot,
                verificationMode: verificationMode,
                progressViewModel: progressViewModel,
                onProgress: onProgress,
                onComplete: {},
                shouldGenerateMHL: shouldGenerateMHL,
                mhlCollector: mhlCollector
            )
        }
        
        onComplete()
    }
    
    // MARK: - Helper Methods
    
    
    // MARK: - Helper Functions

    private static func countFilesInDirectory(at url: URL) async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
                    var count = 0
                    while let fileURL = enumerator?.nextObject() as? URL {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            count += 1
                        }
                    }
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Count how many files already exist at destination with matching size (resume heuristic)
    private static func countAlreadyPresentFiles(
        sourceFiles: [URL],
        sourceBase: URL,
        destRoot: URL,
        verificationMode: VerificationMode
    ) async -> Int {
        let fm = FileManager.default
        var count = 0
        for fileURL in sourceFiles {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let relative = String(fileURL.path.dropFirst(sourceBase.path.count + 1))
                let destURL = destRoot.appendingPathComponent(relative)
                if fm.fileExists(atPath: destURL.path) {
                    let destSize = (try fm.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.int64Value ?? -1
                    if destSize == Int64(values.fileSize ?? -2) {
                        // Optional: when checksum verification is enabled, require a quick checksum for small files
                        if verificationMode.useChecksum, let fsize = values.fileSize, fsize > 0, fsize <= 5 * 1024 * 1024 {
                            do {
                                let srcHash = try await SharedChecksumService.shared.generateChecksum(for: fileURL, type: .sha256, progressCallback: nil)
                                let dstHash = try await SharedChecksumService.shared.generateChecksum(for: destURL, type: .sha256, progressCallback: nil)
                                if srcHash == dstHash { count += 1 }
                            } catch {
                                // If checksum fails, don't count as present; verify phase will catch issues
                            }
                        } else {
                            count += 1
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return count
    }

    // No persistent state; helpers only

    // moved to VerifyService.compare

    private static func performSafetyChecks(source: URL, destinations: [URL]) async throws {
        // Basic safety checks
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BitMatchError.fileNotFound(source)
        }
        
        for dest in destinations {
            let parentDir = dest.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
        }
    }
}
