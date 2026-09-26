// OperationModels.swift - Operation and transfer state models
import Foundation

// MARK: - Operation State
enum OperationState: Equatable {
    case idle
    case notStarted
    case inProgress
    case copying
    case verifying
    case paused(PauseInfo)
    case resuming
    case completed(OperationCompletionInfo)
    case failed
    case cancelled
    
    var isActive: Bool {
        switch self {
        case .inProgress, .copying, .verifying, .resuming: return true
        default: return false
        }
    }
    
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
    
    var canPause: Bool {
        switch self {
        case .inProgress, .copying, .verifying: return true
        default: return false
        }
    }
    
    var canResume: Bool {
        if case .paused = self { return true }
        return false
    }
    
    var canCancel: Bool {
        switch self {
        case .inProgress, .copying, .verifying, .paused, .resuming: return true
        default: return false
        }
    }
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .copying: return "Copying Files"
        case .verifying: return "Verifying"
        case .paused: return "Paused"
        case .resuming: return "Resuming"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct PauseInfo: Codable, Equatable {
    let pausedAt: Date
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int
    let bytesProcessed: Int64
    let reason: PauseReason
    
    enum PauseReason: Codable, Equatable {
        case userRequested
        case systemSleep
        case lowBattery
        case backgrounded
        case error
    }
}

struct OperationCompletionInfo: Equatable {
    let success: Bool
    let message: String
}

// MARK: - Completion State
enum CompletionState: Equatable {
    case idle
    case inProgress
    case success(message: String)
    case issues(message: String)
    case failed(message: String)
    case cancelled(message: String)

    var isActive: Bool {
        if case .inProgress = self { return true }
        return false
    }

    var isComplete: Bool {
        switch self {
        case .success, .issues, .failed, .cancelled: return true
        default: return false
        }
    }
}

// MARK: - Volume Event
struct VolumeEvent {
    let type: VolumeEventType
    let volume: URL
    let timestamp: Date
}

enum VolumeEventType {
    case mounted
    case unmounted
}
