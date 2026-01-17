// Core/Services/OperationManager.swift
import Foundation

/// Manages the lifecycle and state of file operations
final class OperationManager {
    
    // MARK: - Operation Preparation
    
    @MainActor
    static func prepareForOperation(
        jobID: inout UUID,
        jobStart: inout Date,
        currentMode: AppMode,
        fileSelectionViewModel: FileSelectionViewModel,
        progressViewModel: ProgressViewModel,
        verificationMode: VerificationMode,
        onClearResults: () -> Void,
        onClearMHL: () -> Void
    ) {
        onClearResults()
        jobID = UUID()
        jobStart = Date()
        progressViewModel.reset()
        onClearMHL()
        
        // Save initial state for checkpoints
        let initialOperation = OperationStateManager.PersistedOperation(
            id: jobID,
            startTime: jobStart,
            mode: currentMode == .copyAndVerify ? "copy" : "compare",
            sourceURL: fileSelectionViewModel.sourceURL ?? fileSelectionViewModel.leftURL ?? URL(fileURLWithPath: "/"),
            destinationURLs: currentMode == .copyAndVerify ? fileSelectionViewModel.destinationURLs :
                            [fileSelectionViewModel.rightURL].compactMap { $0 },
            verificationMode: verificationMode.rawValue,
            lastProcessedFile: "Starting...",
            processedCount: 0,
            totalCount: 0,
            checkpoints: []
        )
        OperationStateManager.saveState(initialOperation)
    }
    
    // MARK: - Result Management
    
    static func addResults(
        _ newResults: [ResultRow],
        to results: inout [ResultRow],
        maxResultsInMemory: Int
    ) {
        // Memory-aware result addition with error prioritization
        if results.count + newResults.count > maxResultsInMemory {
            let errors = results.filter { !$0.status.contains("✅") && !$0.status.contains("Match") }
            let keepCount = maxResultsInMemory / 2
            let matchesToKeep = max(0, keepCount - errors.count)
            let matches = results.filter { $0.status.contains("✅") || $0.status.contains("Match") }.suffix(matchesToKeep)
            results = Array(errors + matches)
        }
        results.append(contentsOf: newResults)
    }
    
    // MARK: - Cleanup Operations
    
    static func cleanupTemporaryFiles(at urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    await cleanupTempFilesAt(url)
                }
            }
        }
    }
    
    private static func cleanupTempFilesAt(_ url: URL) async {
        do {
            let fileManager = FileManager.default
            let tempItems = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)

            for item in tempItems {
                let fileName = item.lastPathComponent
                // SAFETY FIX: Use hasPrefix("._") instead of contains("._")
                // Resource fork files always START with "._" (e.g., "._Document.pdf")
                // Using contains("._") was too broad and could match legitimate files like "video_01._backup.mov"
                // Also use exact matches for .DS_Store and Thumbs.db
                if fileName.hasPrefix("._") || fileName == ".DS_Store" || fileName == "Thumbs.db" {
                    try? fileManager.removeItem(at: item)
                }
            }
        } catch {
            SharedLogger.error("Cleanup error at \(url.path): \(error)", category: .transfer)
        }
    }
    
    // MARK: - Operation State Management
    
    static func savePartialResults(_ results: [ResultRow], jobID: UUID) {
        guard results.count > 100 else { return }
        
        // Create checkpoint using the service method
        OperationStateManager.createCheckpoint(
            for: jobID,
            filesProcessed: results.count,
            lastFile: results.last?.path ?? "unknown"
        )
    }
    
    // MARK: - Pause/Resume Support
    
    static func checkPause() async {
        // Small delay to allow UI updates and pause detection
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        
        // Check if operation should be paused
        await Task.yield() // Allow other tasks to run
    }
}