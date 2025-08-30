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
        
        // Use fake operations if dev mode is enabled
        if DevModeManager.shared.isDevModeEnabled {
            print("🎭 Using fake comparison operations")
            try await performFakeComparison(
                left: left,
                right: right,
                verificationMode: verificationMode,
                progressViewModel: progressViewModel,
                onProgress: onProgress,
                onComplete: onComplete
            )
            return
        }
        
        // Count files for progress tracking
        let totalFiles = try await FileOperationsService.countFiles(at: left)
        await MainActor.run {
            progressViewModel.setFileCountTotal(totalFiles)
        }
        
        let workers = ProcessInfo.processInfo.activeProcessorCount
        let needsMHL = shouldGenerateMHL
        
        // Collect all files to compare
        let filesToCompare = await Task {
            var files: [URL] = []
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(
                at: left,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    do {
                        if try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                            files.append(fileURL)
                        }
                    } catch {
                        print("Error checking file \(fileURL.path): \(error)")
                    }
                }
            }
            return files
        }.value
        
        // Process comparisons concurrently
        try await withThrowingTaskGroup(of: ResultRow.self) { group in
            let semaphore = AsyncSemaphore(count: workers)
            
            for fileURL in filesToCompare {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    
                    let relativePath = String(fileURL.path.dropFirst(left.path.count + 1))
                    let counterpart = right.appendingPathComponent(relativePath)
                    
                    // Check if counterpart exists
                    guard FileManager.default.fileExists(atPath: counterpart.path) else {
                        return ResultRow(path: relativePath, status: "Missing in Destination", size: 0, checksum: nil)
                    }
                    
                    // Update progress
                    await MainActor.run {
                        progressViewModel.setCurrentFile(fileURL.lastPathComponent)
                    }
                    
                    // Perform comparison
                    let result = await FileOperationsService.compareFile(
                        leftURL: fileURL,
                        rightURL: counterpart,
                        relativePath: relativePath,
                        verificationMode: verificationMode
                    )
                    
                    // Collect checksum for MHL if needed
                    if needsMHL && result.status == .match {
                        if let collector = mhlCollector {
                            do {
                                try await MHLOperationService.collectMHLEntry(
                                    for: counterpart,
                                    algorithm: .sha256, // Use SHA-256 for MHL
                                    collector: collector
                                )
                            } catch {
                                print("Failed to collect MHL entry: \(error)")
                            }
                        }
                    }
                    
                    return result
                }
            }
            
            // Process results in batches
            var batch: [ResultRow] = []
            batch.reserveCapacity(50)
            
            while let row = try await group.next() {
                await OperationManager.checkPause()
                
                await MainActor.run {
                    progressViewModel.incrementFileCompleted()
                    if row.status == .match {
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
        try await checkForExtraFiles(in: right, comparedTo: left, onProgress: onProgress)
        
        onComplete()
    }
    
    // MARK: - Copy and Verify Operations
    
    static func performCopyAndVerify(
        source: URL,
        destinations: [URL],
        verificationMode: VerificationMode,
        progressViewModel: ProgressViewModel,
        onProgress: @escaping ([ResultRow]) -> Void,
        onComplete: @escaping () -> Void,
        shouldGenerateMHL: Bool,
        mhlCollector: MHLOperationService.MHLCollectorActor?
    ) async throws {
        
        // Use fake operations if dev mode is enabled
        if DevModeManager.shared.isDevModeEnabled {
            print("🎭 Using fake copy and verify operations")
            try await performFakeCopyAndVerify(
                source: source,
                destinations: destinations,
                verificationMode: verificationMode,
                progressViewModel: progressViewModel,
                onProgress: onProgress,
                onComplete: onComplete
            )
            return
        }
        
        // Safety checks
        try await FileOperationsService.performSafetyChecks(
            source: source,
            destinations: destinations
        )
        
        // Copy files to all destinations concurrently
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        
        await withThrowingTaskGroup(of: Void.self) { group in
            for destination in destinations {
                group.addTask {
                    try await FileOperationsService.copyAllSafely(
                        from: source,
                        toRoot: destination,
                        workers: workers,
                        onProgress: { fileName, fileSize in
                            Task { @MainActor in
                                progressViewModel.setCurrentFile(fileName)
                                progressViewModel.updateBytesProcessed(fileSize)
                            }
                        },
                        onError: { fileName, error in
                            print("Copy error for \(fileName): \(error)")
                        }
                    )
                }
            }
        }
        
        // Verify copied files
        for destination in destinations {
            try await performComparison(
                left: source,
                right: destination,
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
    
    private static func checkForExtraFiles(
        in destination: URL,
        comparedTo source: URL,
        onProgress: @escaping ([ResultRow]) -> Void
    ) async throws {
        
        // Collect source file paths using non-async approach
        let sourceFiles = await Task.detached {
            return await collectFilePathsSync(at: source, relativeTo: source)
        }.value
        
        // Check destination for extra files using non-async approach
        var extraFiles: [ResultRow] = []
        let destinationFileData = await Task.detached {
            return await collectFilePathsWithFullPaths(at: destination, relativeTo: destination)
        }.value
        
        for (relativePath, fullPath) in destinationFileData {
            if !sourceFiles.contains(relativePath) {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fullPath.path)[.size] as? Int64) ?? 0
                extraFiles.append(ResultRow(
                    path: relativePath,
                    status: "Extra in Destination",
                    size: fileSize,
                    checksum: nil
                ))
            }
            
            if extraFiles.count >= 50 {
                onProgress(extraFiles)
                extraFiles.removeAll()
            }
        }
        
        if !extraFiles.isEmpty {
            onProgress(extraFiles)
        }
    }
    
    // MARK: - Fake Operations for Dev Mode
    
    private static func performFakeComparison(
        left: URL,
        right: URL,
        verificationMode: VerificationMode,
        progressViewModel: ProgressViewModel,
        onProgress: @escaping ([ResultRow]) -> Void,
        onComplete: @escaping () -> Void
    ) async throws {
        
        let fakeFileCount = Int.random(in: 150...450)
        await MainActor.run {
            progressViewModel.setFileCountTotal(fakeFileCount)
            progressViewModel.startProgressTracking()
        }
        
        print("🎭 Starting fake comparison of \(fakeFileCount) files")
        
        try await DevModeManager.simulateFakeVerifyProgress(
            totalFiles: fakeFileCount,
            sourceURL: left,
            destURL: right,
            onProgress: { fileName in
                progressViewModel.setCurrentFile(fileName)
            },
            onResult: { result in
                progressViewModel.incrementFileCompleted()
                // Add fake bytes for speed calculation during verification
                let fakeFileSize = Int64.random(in: 15_000_000...85_000_000) // 15-85 MB per file
                progressViewModel.updateBytesProcessed(fakeFileSize)
                if result.status == .match {
                    progressViewModel.incrementMatch()
                }
                onProgress([result])
            }
        )
        
        // Clear current file display when complete
        await MainActor.run {
            progressViewModel.clearCurrentFile()
        }
        
        onComplete()
    }
    
    private static func performFakeCopyAndVerify(
        source: URL,
        destinations: [URL],
        verificationMode: VerificationMode,
        progressViewModel: ProgressViewModel,
        onProgress: @escaping ([ResultRow]) -> Void,
        onComplete: @escaping () -> Void
    ) async throws {
        
        let fakeFileCount = Int.random(in: 150...450)
        await MainActor.run {
            progressViewModel.setFileCountTotal(fakeFileCount)
            progressViewModel.startProgressTracking()
        }
        
        print("🎭 Starting fake copy and verify of \(fakeFileCount) files to \(destinations.count) destinations")
        
        // Simulate copy phase
        try await DevModeManager.simulateFakeCopyProgress(
            totalFiles: fakeFileCount,
            onProgress: { fileName, fileSize in
                progressViewModel.setCurrentFile(fileName)
                progressViewModel.updateBytesProcessed(fileSize)
            },
            onError: { fileName, error in
                print("🎭 Fake copy error for \(fileName): \(error)")
            }
        )
        
        // Simulate verify phase for each destination
        for (index, destination) in destinations.enumerated() {
            print("🎭 Fake verifying destination \(index + 1)/\(destinations.count)")
            
            try await DevModeManager.simulateFakeVerifyProgress(
                totalFiles: fakeFileCount,
                sourceURL: source,
                destURL: destination,
                onProgress: { fileName in
                    progressViewModel.setCurrentFile(fileName)
                },
                onResult: { result in
                    progressViewModel.incrementFileCompleted()
                    // Add fake bytes for speed calculation during verification
                    let fakeFileSize = Int64.random(in: 15_000_000...85_000_000) // 15-85 MB per file
                    progressViewModel.updateBytesProcessed(fakeFileSize)
                    if result.status == .match {
                        progressViewModel.incrementMatch()
                    }
                    onProgress([result])
                }
            )
        }
        
        // Clear current file display when complete
        await MainActor.run {
            progressViewModel.clearCurrentFile()
        }
        
        onComplete()
    }
    
    // MARK: - Sync File Collection Helpers
    
    private static func collectFilePathsSync(at url: URL, relativeTo base: URL) async -> Set<String> {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                var files = Set<String>()
                let fileManager = FileManager.default
                
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: files)
                    return
                }
                
                let enumeratorArray = Array(enumerator)
                for case let fileURL as URL in enumeratorArray {
                    do {
                        if try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                            let relativePath = String(fileURL.path.dropFirst(base.path.count + 1))
                            files.insert(relativePath)
                        }
                    } catch {
                        print("Error checking file \(fileURL.path): \(error)")
                    }
                }
                continuation.resume(returning: files)
            }
        }
    }
    
    private static func collectFilePathsWithFullPaths(at url: URL, relativeTo base: URL) async -> [(String, String)] {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                var files: [(String, String)] = []
                let fileManager = FileManager.default
                
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: files)
                    return
                }
                
                let enumeratorArray = Array(enumerator)
                for case let fileURL as URL in enumeratorArray {
                    do {
                        if try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                            let relativePath = String(fileURL.path.dropFirst(base.path.count + 1))
                            files.append((relativePath, fileURL.path))
                        }
                    } catch {
                        print("Error checking file \(fileURL.path): \(error)")
                    }
                }
                continuation.resume(returning: files)
            }
        }
    }
}