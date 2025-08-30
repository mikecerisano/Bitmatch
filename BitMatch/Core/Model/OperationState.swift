// Core/Models/OperationState.swift
import Foundation

// MARK: - Operation State Machine
enum OperationState: Equatable {
    case idle
    case preparing
    case copying(progress: Double, currentFile: String?)
    case verifying(progress: Double, currentFile: String?)
    case paused(resumeFrom: OperationPhase)
    case completed(CompletionInfo)
    case cancelled
    case failed(BitMatchError)
    
    enum OperationPhase: Equatable {
        case copying(progress: Double)
        case verifying(progress: Double)
    }
    
    struct CompletionInfo: Equatable {
        let success: Bool
        let message: String
        let fileCount: Int
        let matchCount: Int
        let issueCount: Int
        let duration: TimeInterval
    }
    
    var isActive: Bool {
        switch self {
        case .preparing, .copying, .verifying, .paused:
            return true
        default:
            return false
        }
    }
    
    var canCancel: Bool {
        switch self {
        case .preparing, .copying, .verifying, .paused:
            return true
        default:
            return false
        }
    }
    
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
    
    var progress: Double {
        switch self {
        case .copying(let p, _), .verifying(let p, _):
            return p
        case .paused(let phase):
            switch phase {
            case .copying(let p), .verifying(let p):
                return p
            }
        default:
            return 0
        }
    }
}

// MARK: - BitMatch Error Types
enum BitMatchError: LocalizedError, Equatable {
    case insufficientSpace(needed: Int64, available: Int64)
    case noWritePermission(path: String)
    case noReadPermission(path: String)
    case checksumMismatch(file: String, expected: String, actual: String)
    case sourceNotFound(path: String)
    case destinationExists(path: String)
    case symlinkLoop(path: String)
    case networkDriveTimeout(path: String)
    case tooManyFiles(count: Int, limit: Int)
    case operationCancelled
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientSpace(let needed, let available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let neededStr = formatter.string(fromByteCount: needed)
            let availStr = formatter.string(fromByteCount: available)
            return "Insufficient disk space. Need \(neededStr) but only \(availStr) available."
            
        case .noWritePermission(let path):
            return "No write permission for: \(URL(fileURLWithPath: path).lastPathComponent)"
            
        case .noReadPermission(let path):
            return "No read permission for: \(URL(fileURLWithPath: path).lastPathComponent)"
            
        case .checksumMismatch(let file, _, _):
            return "Checksum verification failed for: \(file)"
            
        case .sourceNotFound(let path):
            return "Source not found: \(URL(fileURLWithPath: path).lastPathComponent)"
            
        case .destinationExists(let path):
            return "Destination already exists: \(URL(fileURLWithPath: path).lastPathComponent)"
            
        case .symlinkLoop(let path):
            return "Symbolic link loop detected at: \(URL(fileURLWithPath: path).lastPathComponent)"
            
        case .networkDriveTimeout(let path):
            return "Network drive timeout: \(URL(fileURLWithPath: path).lastPathComponent)"
            
        case .tooManyFiles(let count, let limit):
            return "Too many files (\(count)). Maximum supported: \(limit)"
            
        case .operationCancelled:
            return "Operation was cancelled"
            
        case .unknown(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .insufficientSpace:
            return "Free up disk space on the destination drive and try again."
            
        case .noWritePermission:
            return "Check folder permissions or choose a different destination."
            
        case .noReadPermission:
            return "Check folder permissions or choose a different source."
            
        case .checksumMismatch:
            return "The file may be corrupted. Try copying again or check the source."
            
        case .sourceNotFound:
            return "Ensure the source folder exists and is accessible."
            
        case .destinationExists:
            return "Choose a different destination or enable auto-numbering."
            
        case .symlinkLoop:
            return "Check for circular symbolic links in the folder structure."
            
        case .networkDriveTimeout:
            return "Check network connection and try again."
            
        case .tooManyFiles:
            return "Consider processing folders in smaller batches."
            
        default:
            return nil
        }
    }
}

// MARK: - File Operation Queue
actor FileOperationQueue {
    struct FileOperation {
        let id = UUID()
        let sourceURL: URL
        let destinationURL: URL?
        let type: OperationType
        var status: Status = .pending
        var error: Error?
        
        enum OperationType {
            case copy
            case verify
            case checksum
        }
        
        enum Status {
            case pending
            case inProgress
            case completed
            case failed
        }
    }
    
    private var operations: [FileOperation] = []
    private var completed: [FileOperation] = []
    private var currentBatch: [FileOperation] = []
    private let maxBatchSize: Int
    
    init(maxBatchSize: Int = 10) {
        self.maxBatchSize = maxBatchSize
    }
    
    func addOperation(_ op: FileOperation) {
        operations.append(op)
    }
    
    func addOperations(_ ops: [FileOperation]) {
        operations.append(contentsOf: ops)
    }
    
    func nextBatch(size: Int? = nil) -> [FileOperation] {
        let batchSize = min(size ?? maxBatchSize, operations.count)
        guard batchSize > 0 else { return [] }
        
        let batch = Array(operations.prefix(batchSize))
        operations.removeFirst(batchSize)
        currentBatch.append(contentsOf: batch)
        return batch
    }
    
    func completeOperation(_ op: FileOperation) {
        if let index = currentBatch.firstIndex(where: { $0.id == op.id }) {
            var completedOp = currentBatch.remove(at: index)
            completedOp.status = .completed
            completed.append(completedOp)
        }
    }
    
    func failOperation(_ op: FileOperation, error: Error) {
        if let index = currentBatch.firstIndex(where: { $0.id == op.id }) {
            var failedOp = currentBatch.remove(at: index)
            failedOp.status = .failed
            failedOp.error = error
            completed.append(failedOp)
        }
    }
    
    func progress() -> (pending: Int, inProgress: Int, completed: Int, failed: Int, total: Int) {
        let failed = completed.filter { $0.status == .failed }.count
        let done = completed.filter { $0.status == .completed }.count
        let total = operations.count + currentBatch.count + completed.count
        
        return (
            pending: operations.count,
            inProgress: currentBatch.count,
            completed: done,
            failed: failed,
            total: total
        )
    }
    
    func reset() {
        operations.removeAll()
        completed.removeAll()
        currentBatch.removeAll()
    }
    
    func hasMoreOperations() -> Bool {
        return !operations.isEmpty
    }
}
