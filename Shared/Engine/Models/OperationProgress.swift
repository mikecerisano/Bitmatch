// OperationProgress.swift - Progress the engine reports while it runs.
import Foundation

// MARK: - Progress Stage
enum ProgressStage: Codable {
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
struct OperationProgress: Codable {
    let overallProgress: Double
    let currentFile: String?
    let filesProcessed: Int
    let totalFiles: Int
    let currentStage: ProgressStage
    let speed: Double? // bytes per second
    let timeRemaining: TimeInterval?
    let reusedCopies: Int?
    
    // Enhanced timing information
    let elapsedTime: TimeInterval?
    let averageSpeed: Double?
    let peakSpeed: Double?
    let bytesProcessed: Int64?
    let totalBytes: Int64?
    let stageProgress: Double? // Progress within current stage
    // Per-destination progress (optional)
    let perDestinationTotals: [Int]?
    let perDestinationCompleted: [Int]?
    
    // Convenience initializer for backward compatibility
    init(overallProgress: Double, currentFile: String?, filesProcessed: Int, totalFiles: Int, currentStage: ProgressStage, speed: Double?, timeRemaining: TimeInterval?, reusedCopies: Int? = nil) {
        self.overallProgress = overallProgress
        self.currentFile = currentFile
        self.filesProcessed = filesProcessed
        self.totalFiles = totalFiles
        self.currentStage = currentStage
        self.speed = speed
        self.timeRemaining = timeRemaining
        self.reusedCopies = reusedCopies
        self.elapsedTime = nil
        self.averageSpeed = nil
        self.peakSpeed = nil
        self.bytesProcessed = nil
        self.totalBytes = nil
        self.stageProgress = nil
        self.perDestinationTotals = nil
        self.perDestinationCompleted = nil
    }
    
    // Full initializer with timing information
    init(overallProgress: Double, currentFile: String?, filesProcessed: Int, totalFiles: Int, currentStage: ProgressStage, speed: Double?, timeRemaining: TimeInterval?, elapsedTime: TimeInterval?, averageSpeed: Double?, peakSpeed: Double?, bytesProcessed: Int64?, totalBytes: Int64?, stageProgress: Double? = nil, reusedCopies: Int? = nil, perDestinationTotals: [Int]? = nil, perDestinationCompleted: [Int]? = nil) {
        self.overallProgress = overallProgress
        self.currentFile = currentFile
        self.filesProcessed = filesProcessed
        self.totalFiles = totalFiles
        self.currentStage = currentStage
        self.speed = speed
        self.timeRemaining = timeRemaining
        self.reusedCopies = reusedCopies
        self.elapsedTime = elapsedTime
        self.averageSpeed = averageSpeed
        self.peakSpeed = peakSpeed
        self.bytesProcessed = bytesProcessed
        self.totalBytes = totalBytes
        self.stageProgress = stageProgress
        self.perDestinationTotals = perDestinationTotals
        self.perDestinationCompleted = perDestinationCompleted
    }
}
