import Foundation
import SwiftUI

@MainActor
final class ProgressViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var interpolatedProgress: Double = 0.0
    @Published var currentFileProgress: Double = 0.0
    @Published var progressMessage = "Ready"
    @Published var bytesPerSecond: Double = 0
    @Published var filesPerSecond: Double = 0
    @Published var estimatedTimeRemaining: TimeInterval?
    
    // MARK: - File Counting
    @Published var fileCountTotal = 0
    @Published var fileCountCompleted = 0
    @Published var matchCount = 0
    
    // MARK: - Current File Info
    @Published var currentFileSize: Int64 = 0
    @Published var currentFileBytesProcessed: Int64 = 0
    @Published var currentFileName: String? = nil  // FIXED: Now properly tracked
    
    // MARK: - Private Properties
    private var progressTimer: Timer?
    private var lastProgressUpdate = Date()
    private var lastUpdateTime = Date()
    private var lastFileCount = 0
    private var lastBytesProcessed: Int64 = 0
    private var isCountingFiles = false
    
    // MARK: - Public Properties (FIXED: Exposed for reporting)
    private(set) var totalBytesProcessed: Int64 = 0
    
    // MARK: - Computed Properties
    var verificationProgress: Double {
        guard fileCountTotal > 0 else { return 0 }
        return Double(fileCountCompleted) / Double(fileCountTotal)
    }
    
    var displayProgress: Double {
        // Only show interpolated progress if we have valid data
        if fileCountTotal > 0 && !isCountingFiles {
            // FIXED: Better bounds checking
            return max(0, min(1, interpolatedProgress))
        }
        return 0
    }
    
    // MARK: - Progress Management
    func startProgressTracking() {
        reset()
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.updateInterpolatedProgress()
            }
        }
    }
    
    func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
        interpolatedProgress = 0
    }
    
    func reset() {
        interpolatedProgress = 0
        fileCountTotal = 0
        fileCountCompleted = 0
        matchCount = 0
        bytesPerSecond = 0
        filesPerSecond = 0
        estimatedTimeRemaining = nil
        progressMessage = "Ready"
        totalBytesProcessed = 0
        lastUpdateTime = Date()
        lastFileCount = 0
        lastBytesProcessed = 0
        isCountingFiles = false
        currentFileName = nil  // FIXED: Reset current file
        currentFileSize = 0
        currentFileBytesProcessed = 0
    }
    
    func setFileCountTotal(_ count: Int) {
        fileCountTotal = count
        isCountingFiles = false
    }
    
    func incrementFileCompleted(_ count: Int = 1) {
        fileCountCompleted += count
        lastProgressUpdate = Date()
        updatePerformanceMetrics()
        // Force immediate progress update for the first few files
        if fileCountCompleted <= 3 {
            updateInterpolatedProgress()
        }
    }
    
    func incrementMatch() {
        matchCount += 1
    }
    
    func updateBytesProcessed(_ bytes: Int64) {
        totalBytesProcessed += bytes
        updatePerformanceMetrics()
    }
    
    func setProgressMessage(_ message: String) {
        progressMessage = message
    }
    
    // MARK: - New Methods for File Tracking
    func setCurrentFile(_ fileName: String, size: Int64 = 0) {
        currentFileName = fileName
        currentFileSize = size
        currentFileBytesProcessed = 0
    }
    
    func updateCurrentFileProgress(_ bytesProcessed: Int64) {
        currentFileBytesProcessed = bytesProcessed
        if currentFileSize > 0 {
            currentFileProgress = Double(bytesProcessed) / Double(currentFileSize)
        }
    }
    
    func clearCurrentFile() {
        currentFileName = nil
        currentFileSize = 0
        currentFileBytesProcessed = 0
        currentFileProgress = 0
    }
    
    // MARK: - Public Getters for Reporting
    func getTotalBytesProcessed() -> Int64 {
        return totalBytesProcessed
    }
    
    // MARK: - Private Methods
    private func updateInterpolatedProgress() {
        guard fileCountTotal > 0 && !isCountingFiles else {
            interpolatedProgress = 0
            return
        }
        
        let baseProgress = Double(fileCountCompleted) / Double(fileCountTotal)
        let now = Date()
        let timeSinceLastFile = now.timeIntervalSince(lastProgressUpdate)
        
        // Always show immediate progress based on file completion
        let targetProgress = baseProgress
        
        // Add smooth interpolation if we have performance metrics, otherwise use direct progress
        if filesPerSecond > 0 && fileCountTotal > fileCountCompleted {
            let avgFileTime = 1.0 / filesPerSecond
            let estimatedFileProgress = min(1.0, timeSinceLastFile / avgFileTime)
            let fileContribution = estimatedFileProgress / Double(fileCountTotal)
            let interpolatedTarget = min(1.0, baseProgress + fileContribution)
            
            // Use interpolated progress for smoother animation
            let smoothingFactor = 0.15
            let newProgress = interpolatedProgress + (interpolatedTarget - interpolatedProgress) * smoothingFactor
            
            if abs(newProgress - interpolatedProgress) > 0.001 {
                withAnimation(.linear(duration: 0.1)) {
                    interpolatedProgress = max(0, min(1, newProgress))
                }
            }
        } else {
            // Fallback to direct progress if no performance metrics yet
            withAnimation(.linear(duration: 0.1)) {
                interpolatedProgress = max(0, min(1, targetProgress))
            }
        }
    }
    
    private func updatePerformanceMetrics() {
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastUpdateTime)
        
        guard timeDelta >= 0.5 else { return }  // Reduced from 1.0 to 0.5 seconds
        
        let filesDelta = fileCountCompleted - lastFileCount
        filesPerSecond = Double(filesDelta) / timeDelta
        
        let bytesDelta = totalBytesProcessed - lastBytesProcessed
        bytesPerSecond = Double(bytesDelta) / timeDelta
        
        if filesPerSecond > 0 && fileCountTotal > fileCountCompleted {
            let filesRemaining = fileCountTotal - fileCountCompleted
            estimatedTimeRemaining = Double(filesRemaining) / filesPerSecond
        }
        
        lastUpdateTime = now
        lastFileCount = fileCountCompleted
        lastBytesProcessed = totalBytesProcessed
    }
    
    deinit {
        progressTimer?.invalidate()
    }
}

// MARK: - Progress Display Helpers
extension ProgressViewModel {
    var formattedSpeed: String? {
        if filesPerSecond > 0 {
            return String(format: "%.0f files/s", filesPerSecond)
        } else if bytesPerSecond > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .binary
            return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
        }
        return nil
    }
    
    var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining else { return nil }
        
        if remaining < 60 {
            return "<1 min"
        } else if remaining < 3600 {
            return "\(Int(remaining / 60)) min"
        } else {
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}
