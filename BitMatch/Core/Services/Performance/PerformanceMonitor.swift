// Core/Services/Performance/PerformanceMonitor.swift
import Foundation
import os.signpost

/// Monitors app performance and provides insights
class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let subsystem = "com.bitmatch.performance"
    private lazy var log = OSLog(subsystem: subsystem, category: "PerformanceMonitor")
    
    private var operations: [String: Date] = [:]
    
    private init() {}
    
    // MARK: - Operation Timing
    
    func startOperation(_ name: String) {
        operations[name] = Date()
        os_signpost(.begin, log: log, name: "Operation", "%{public}s", name)
        AppLogger.debug("Started operation: \(name)", category: .general)
    }
    
    func endOperation(_ name: String) -> TimeInterval? {
        guard let startTime = operations.removeValue(forKey: name) else {
            AppLogger.warning("Attempted to end non-existent operation: \(name)", category: .general)
            return nil
        }
        
        let duration = Date().timeIntervalSince(startTime)
        os_signpost(.end, log: log, name: "Operation", "%{public}s completed in %.2fs", name, duration)
        
        AppLogger.info("Operation '\(name)' completed in \(String(format: "%.2f", duration))s", category: .general)
        
        // Log slow operations
        if duration > 5.0 {
            AppLogger.warning("Slow operation detected: '\(name)' took \(String(format: "%.2f", duration))s", category: .general)
        }
        
        return duration
    }
    
    // MARK: - Transfer Performance
    
    func recordTransferMetrics(
        totalBytes: Int64,
        duration: TimeInterval,
        operation: String = "transfer"
    ) {
        guard duration > 0 else { return }
        
        let bytesPerSecond = Double(totalBytes) / duration
        let mbPerSecond = bytesPerSecond / (1024 * 1024)
        
        AppLogger.info(
            "Transfer performance - \(operation): \(formatBytes(totalBytes)) in \(String(format: "%.1f", duration))s (\(String(format: "%.1f", mbPerSecond)) MB/s)",
            category: .transfer
        )
        
        // Track performance trends
        recordPerformanceSample(operation: operation, mbPerSecond: mbPerSecond)
    }
    
    // MARK: - Memory Monitoring
    
    func logMemoryUsage(_ context: String = "") {
        let memoryUsage = getMemoryUsage()
        let contextStr = context.isEmpty ? "" : " [\(context)]"
        
        AppLogger.debug(
            "Memory usage\(contextStr): \(String(format: "%.1f", memoryUsage.used))MB used, \(String(format: "%.1f", memoryUsage.free))MB free",
            category: .general
        )
    }
    
    // MARK: - Performance Samples
    
    private var performanceSamples: [String: [Double]] = [:]
    
    private func recordPerformanceSample(operation: String, mbPerSecond: Double) {
        performanceSamples[operation, default: []].append(mbPerSecond)
        
        // Keep only last 10 samples
        if performanceSamples[operation]!.count > 10 {
            performanceSamples[operation]!.removeFirst()
        }
        
        // Log performance trend
        if let samples = performanceSamples[operation], samples.count >= 3 {
            let avgSpeed = samples.reduce(0, +) / Double(samples.count)
            let trend = samples.suffix(3).reduce(0, +) / 3.0
            
            let trendDirection = trend > avgSpeed ? "↗" : (trend < avgSpeed ? "↘" : "→")
            AppLogger.debug(
                "Performance trend \(trendDirection): \(operation) avg: \(String(format: "%.1f", avgSpeed))MB/s, recent: \(String(format: "%.1f", trend))MB/s",
                category: .transfer
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func getMemoryUsage() -> (used: Double, free: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / (1024 * 1024)
            let freeMB = Double(info.virtual_size - info.resident_size) / (1024 * 1024)
            return (used: usedMB, free: freeMB)
        }
        
        return (used: 0, free: 0)
    }
}

// MARK: - Convenience Methods

extension PerformanceMonitor {
    /// Measures execution time of a closure
    func measure<T>(_ name: String, _ closure: () throws -> T) rethrows -> T {
        startOperation(name)
        defer { endOperation(name) }
        return try closure()
    }
    
    /// Measures execution time of an async closure
    func measure<T>(_ name: String, _ closure: () async throws -> T) async rethrows -> T {
        startOperation(name)
        defer { endOperation(name) }
        return try await closure()
    }
}