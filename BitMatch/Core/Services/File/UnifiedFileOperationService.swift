// Core/Services/File/UnifiedFileOperationService.swift
import Foundation

/// Unified service that coordinates all file operations with safety, progress tracking, and cleanup
final class UnifiedFileOperationService {
    static let shared = UnifiedFileOperationService()
    private init() {}
    
    // MARK: - High-level File Operations
    
    /// Perform a complete file operation with safety checks, progress tracking, and cleanup
    func performSecureCopyOperation(
        from source: URL,
        toDestinations destinations: [URL],
        verificationMode: VerificationMode = .standard,
        workers: Int = 4,
        onProgress: @escaping (String, Int64) -> Void,
        onError: @escaping (String, Error) -> Void
    ) async throws {
        
        // Step 1: Safety validation
        try await SafetyValidator.performSafetyChecks(source: source, destinations: destinations)
        
        // Step 2: Count files for progress tracking
        let totalFiles = try await FileCounter.countFiles(at: source)
        SharedLogger.info("Total files to process: \(totalFiles)", category: .transfer)
        
        // Step 3: Perform copying to each destination
        for destination in destinations {
            try await FileCopyService.copyAllSafely(
                from: source,
                toRoot: destination,
                verificationMode: verificationMode,
                workers: workers,
                preEnumeratedFiles: nil,
                pauseCheck: nil,
                onProgress: onProgress,
                onError: onError
            )
        }
        
        // Step 4: Cleanup any temp files
        TempFileManager.cleanupAllTempFiles()
    }
    
    /// Get file count with progress callback
    func getFileCount(at url: URL, onProgress: ((Int) -> Void)? = nil) async throws -> Int {
        let count = try await FileCounter.countFiles(at: url)
        onProgress?(count)
        return count
    }
    
    /// Validate multiple operations before execution
    func validateMultipleOperations(_ operations: [(source: URL, destinations: [URL])]) async throws {
        for operation in operations {
            try await SafetyValidator.performSafetyChecks(
                source: operation.source, 
                destinations: operation.destinations
            )
        }
    }
    
    /// Get system info for operation planning
    func getOperationCapabilities() -> OperationCapabilities {
        return OperationCapabilities(
            maxConcurrentWorkers: ProcessInfo.processInfo.activeProcessorCount,
            availableMemory: getAvailableMemory(),
            tempFileCount: TempFileManager.activeTempFileCount
        )
    }
    
    // MARK: - Temp File Management
    
    func registerTempFile(_ url: URL) {
        TempFileManager.addTempFile(url)
    }
    
    func cleanupTempFile(_ url: URL) {
        TempFileManager.removeTempFile(url)
    }
    
    func cleanupAllTempFiles() {
        TempFileManager.cleanupAllTempFiles()
    }
    
    // MARK: - Private Utilities
    
    private func getAvailableMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
}

// MARK: - Supporting Types

struct OperationCapabilities {
    let maxConcurrentWorkers: Int
    let availableMemory: UInt64
    let tempFileCount: Int
    
    var recommendedWorkers: Int {
        // Conservative approach: use 75% of available cores
        return max(1, Int(Double(maxConcurrentWorkers) * 0.75))
    }
    
    var memoryPressure: MemoryPressureLevel {
        let gbMemory = Double(availableMemory) / (1024 * 1024 * 1024)
        switch gbMemory {
        case 0..<2.0:
            return .high
        case 2.0..<8.0:
            return .medium
        default:
            return .low
        }
    }
}

enum MemoryPressureLevel {
    case low, medium, high
    
    var maxConcurrentOperations: Int {
        switch self {
        case .low: return 4
        case .medium: return 2
        case .high: return 1
        }
    }
}
