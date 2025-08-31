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

struct PauseInfo: Equatable {
    let pausedAt: Date
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int
    let bytesProcessed: Int64
    let reason: PauseReason
    
    enum PauseReason: Equatable {
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
    
    var isActive: Bool {
        if case .inProgress = self { return true }
        return false
    }
    
    var isComplete: Bool {
        switch self {
        case .success, .issues, .failed: return true
        default: return false
        }
    }
}

// MARK: - Progress Stage
enum ProgressStage {
    case idle
    case preparing
    case copying
    case verifying
    case generating
    case completed
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing..."
        case .copying: return "Copying files..."
        case .verifying: return "Verifying integrity..."
        case .generating: return "Generating reports..."
        case .completed: return "Complete"
        }
    }
}

// MARK: - Operation Progress
struct OperationProgress {
    let overallProgress: Double
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int
    let currentStage: ProgressStage
    let speed: Double? // bytes per second
    let timeRemaining: TimeInterval?
    
    // Enhanced timing information
    let elapsedTime: TimeInterval?
    let averageSpeed: Double?
    let peakSpeed: Double?
    let bytesProcessed: Int64?
    let totalBytes: Int64?
    let stageProgress: Double? // Progress within current stage
    
    var formattedSpeed: String? {
        guard let speed = speed else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(speed)) + "/s"
    }
    
    var formattedAverageSpeed: String? {
        guard let averageSpeed = averageSpeed else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(averageSpeed)) + "/s"
    }
    
    var formattedPeakSpeed: String? {
        guard let peakSpeed = peakSpeed else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(peakSpeed)) + "/s"
    }
    
    var formattedTimeRemaining: String? {
        guard let timeRemaining = timeRemaining else { return nil }
        let hours = Int(timeRemaining / 3600)
        let minutes = Int((timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var formattedElapsedTime: String? {
        guard let elapsedTime = elapsedTime else { return nil }
        let hours = Int(elapsedTime / 3600)
        let minutes = Int((elapsedTime.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(elapsedTime.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var formattedBytesProcessed: String? {
        guard let bytesProcessed = bytesProcessed else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytesProcessed, countStyle: .file)
    }
    
    var formattedTotalBytes: String? {
        guard let totalBytes = totalBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    // Convenience initializer for backward compatibility
    init(overallProgress: Double, currentFile: String?, filesProcessed: Int, totalFiles: Int, currentStage: ProgressStage, speed: Double?, timeRemaining: TimeInterval?) {
        self.overallProgress = overallProgress
        self.currentFile = currentFile
        self.filesProcessed = filesProcessed
        self.totalFiles = totalFiles
        self.currentStage = currentStage
        self.speed = speed
        self.timeRemaining = timeRemaining
        self.elapsedTime = nil
        self.averageSpeed = nil
        self.peakSpeed = nil
        self.bytesProcessed = nil
        self.totalBytes = nil
        self.stageProgress = nil
    }
    
    // Full initializer with timing information
    init(overallProgress: Double, currentFile: String?, filesProcessed: Int, totalFiles: Int, currentStage: ProgressStage, speed: Double?, timeRemaining: TimeInterval?, elapsedTime: TimeInterval?, averageSpeed: Double?, peakSpeed: Double?, bytesProcessed: Int64?, totalBytes: Int64?, stageProgress: Double? = nil) {
        self.overallProgress = overallProgress
        self.currentFile = currentFile
        self.filesProcessed = filesProcessed
        self.totalFiles = totalFiles
        self.currentStage = currentStage
        self.speed = speed
        self.timeRemaining = timeRemaining
        self.elapsedTime = elapsedTime
        self.averageSpeed = averageSpeed
        self.peakSpeed = peakSpeed
        self.bytesProcessed = bytesProcessed
        self.totalBytes = totalBytes
        self.stageProgress = stageProgress
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