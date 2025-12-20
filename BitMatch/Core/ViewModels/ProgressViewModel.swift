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
    @Published var reusedFileCopies = 0 // Count of reused copies (across all destinations)
    
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
    // Per-destination tracking (internal, not published)
    private var perDestinationTotals: [Int] = []
    private var perDestinationCompleted: [Int] = []
    // Rolling average window for bytes/sec
    private var byteSamples: [(time: Date, bytes: Int64)] = []
    private var rateSamples: [(time: Date, bytesDelta: Int64, duration: TimeInterval)] = []
    private let rollingWindowSeconds: TimeInterval = 10
    // Exponential moving average (EMA) for smoother speed display
    private var emaBytesPerSecond: Double? = nil
    private let emaSmoothingSeconds: TimeInterval = 3.0 // ~Finder-like responsiveness
    
    // Planned total bytes (overall across all destinations)
    private var plannedTotalBytes: Int64?
    
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
        reusedFileCopies = 0
        lastUpdateTime = Date()
        lastFileCount = 0
        lastBytesProcessed = 0
        isCountingFiles = false
        currentFileName = nil  // FIXED: Reset current file
        currentFileSize = 0
        currentFileBytesProcessed = 0
        perDestinationTotals = []
        perDestinationCompleted = []
        plannedTotalBytes = nil
        byteSamples.removeAll(keepingCapacity: false)
        rateSamples.removeAll(keepingCapacity: false)
    }

    // MARK: - Reuse Accounting
    func setReusedFileCopies(_ count: Int) {
        reusedFileCopies = max(0, count)
    }
    func incrementReusedFileCopies(by delta: Int) {
        guard delta != 0 else { return }
        reusedFileCopies = max(0, reusedFileCopies + delta)
    }
    
    func setFileCountTotal(_ count: Int) {
        fileCountTotal = count
        isCountingFiles = false
    }

    // Configure per-destination totals
    func configureDestinations(totalPerDestination: Int, count: Int) {
        guard count > 0 else {
            perDestinationTotals = []
            perDestinationCompleted = []
            return
        }
        perDestinationTotals = Array(repeating: totalPerDestination, count: count)
        perDestinationCompleted = Array(repeating: 0, count: count)
    }

    // Mirror overall progress into per-destination progress for UI display
    func mirrorPerDestinationProgress(overallCompleted: Int, overallTotal: Int, destinationCount: Int) {
        guard destinationCount > 0 else { return }
        let perDestTotal = overallTotal > 0 ? max(1, overallTotal / destinationCount) : 0
        if perDestinationTotals.count != destinationCount {
            perDestinationTotals = Array(repeating: perDestTotal, count: destinationCount)
        }
        // Distribute completed across destinations as evenly as possible
        let base = overallCompleted / max(1, destinationCount)
        var remainder = overallCompleted % max(1, destinationCount)
        perDestinationCompleted = (0..<destinationCount).map { _ in
            defer { remainder = max(0, remainder - 1) }
            return base + (remainder > 0 ? 1 : 0)
        }
    }

    // Set explicit per-destination counts from engine
    func setPerDestinationProgress(totals: [Int], completed: [Int]) {
        guard totals.count == completed.count else { return }
        perDestinationTotals = totals
        perDestinationCompleted = completed
    }

    // Whether we currently hold valid per-destination progress data
    func hasPerDestinationData(expectedCount: Int) -> Bool {
        return perDestinationTotals.count == expectedCount && perDestinationCompleted.count == expectedCount
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

    func incrementDestinationCompleted(index: Int) {
        guard index >= 0 && index < perDestinationCompleted.count else { return }
        perDestinationCompleted[index] += 1
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
        
        // Update metrics more often, but still apply smoothing
        guard timeDelta >= 0.25 else { return }
        
        let filesDelta = fileCountCompleted - lastFileCount
        filesPerSecond = Double(filesDelta) / timeDelta
        
        let bytesDelta = totalBytesProcessed - lastBytesProcessed
        let instantaneousBps = Double(bytesDelta) / timeDelta
        bytesPerSecond = instantaneousBps

        // Update EMA with time-aware alpha to keep smooth but responsive
        let alpha = 1 - exp(-timeDelta / emaSmoothingSeconds)
        if let prev = emaBytesPerSecond {
            emaBytesPerSecond = prev + alpha * (instantaneousBps - prev)
        } else {
            emaBytesPerSecond = instantaneousBps
        }

        // Update rolling average samples
        rateSamples.append((time: now, bytesDelta: bytesDelta, duration: timeDelta))
        byteSamples.append((time: now, bytes: totalBytesProcessed))
        // Drop samples older than window
        let cutoff = now.addingTimeInterval(-rollingWindowSeconds)
        while let first = rateSamples.first, first.time < cutoff { rateSamples.removeFirst() }
        while let first = byteSamples.first, first.time < cutoff { byteSamples.removeFirst() }
        
        if filesPerSecond > 0 && fileCountTotal > fileCountCompleted {
            let filesRemaining = fileCountTotal - fileCountCompleted
            estimatedTimeRemaining = Double(filesRemaining) / filesPerSecond
        } else {
            estimatedTimeRemaining = nil
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
    // Configure planned total bytes (overall)
    func setPlannedTotalBytes(_ total: Int64?) {
        plannedTotalBytes = total
    }
    var filesRemaining: Int {
        max(fileCountTotal - fileCountCompleted, 0)
    }
    
    var formattedFilesRemaining: String? {
        guard fileCountTotal > 0 else { return nil }
        return "\(filesRemaining) files"
    }
    
    var formattedAverageDataRate: String? {
        // Prefer EMA, then rolling averages, then instantaneous
        let rate = (emaBytesPerSecond ?? rollingActiveBytesPerSecond ?? rollingBytesPerSecond ?? bytesPerSecond)
        guard rate > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal
        let perSec = formatter.string(fromByteCount: Int64(rate)) + "/s"
        return perSec
    }

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
        // Prefer bytes-based ETA when available
        if let total = plannedTotalBytes, total > 0 {
            let rate = rollingActiveBytesPerSecond ?? rollingBytesPerSecond ?? bytesPerSecond
            if rate > 0 {
                let remainingBytes = max(0, total - totalBytesProcessed)
                let seconds = Double(remainingBytes) / rate
                return formatSeconds(seconds)
            }
        }
        guard let remaining = estimatedTimeRemaining else { return nil }
        return formatSeconds(remaining)
    }

    // Rate over rolling window excluding zero-byte intervals
    private var rollingActiveBytesPerSecond: Double? {
        guard !rateSamples.isEmpty else { return nil }
        let active = rateSamples.filter { $0.bytesDelta > 0 }
        let sumBytes = active.reduce(Int64(0)) { $0 + $1.bytesDelta }
        let sumTime = active.reduce(0.0) { $0 + $1.duration }
        if sumBytes <= 0 || sumTime <= 0 { return nil }
        return Double(sumBytes) / sumTime
    }

    private var rollingBytesPerSecond: Double? {
        guard byteSamples.count >= 2 else { return nil }
        guard let first = byteSamples.first, let last = byteSamples.last else { return nil }
        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 0 else { return nil }
        let db = Double(last.bytes - first.bytes)
        return max(0, db / dt)
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1 min" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Destination progress helpers
extension ProgressViewModel {
    func destinationProgressFractions(expectedCount: Int) -> [Double] {
        guard expectedCount > 0 else { return [] }
        if perDestinationTotals.count == expectedCount && expectedCount == perDestinationCompleted.count {
            return zip(perDestinationCompleted, perDestinationTotals).map { completed, total in
                guard total > 0 else { return 0 }
                let frac = max(0, min(1, Double(completed) / Double(total)))
                return frac
            }
        }
        // Fallback: mirror overall progress across destinations
        let overall = verificationProgress
        return Array(repeating: overall, count: expectedCount)
    }
}
