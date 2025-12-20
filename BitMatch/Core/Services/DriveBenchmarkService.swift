// Core/Services/DriveBenchmarkService.swift
// Quick drive speed benchmarking for accurate time estimates

import Foundation

actor DriveBenchmarkService {
    static let shared = DriveBenchmarkService()

    // Cache speeds by volume UUID to avoid re-benchmarking
    private var readSpeedCache: [String: Double] = [:]  // bytes/sec
    private var writeSpeedCache: [String: Double] = [:]

    // Benchmark settings
    private let testSize: Int = 10 * 1024 * 1024  // 10MB test file
    private let cacheTTL: TimeInterval = 3600  // 1 hour cache
    private var cacheTimestamps: [String: Date] = [:]

    // MARK: - Public API

    /// Get read speed for a volume, benchmarking if needed
    func getReadSpeed(for url: URL) async -> Double? {
        let volumeID = getVolumeID(for: url)

        // Check cache
        if let cached = readSpeedCache[volumeID],
           let timestamp = cacheTimestamps[volumeID],
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        // Benchmark
        guard let speed = await benchmarkRead(at: url) else { return nil }
        readSpeedCache[volumeID] = speed
        cacheTimestamps[volumeID] = Date()
        return speed
    }

    /// Get write speed for a volume, benchmarking if needed
    func getWriteSpeed(for url: URL) async -> Double? {
        let volumeID = getVolumeID(for: url)

        // Check cache
        if let cached = writeSpeedCache[volumeID],
           let timestamp = cacheTimestamps[volumeID],
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        // Benchmark
        guard let speed = await benchmarkWrite(at: url) else { return nil }
        writeSpeedCache[volumeID] = speed
        cacheTimestamps[volumeID] = Date()
        return speed
    }

    /// Estimate transfer time for a given operation
    func estimateTransferTime(
        sourceURL: URL,
        destinationURLs: [URL],
        totalBytes: Int64,
        verificationMode: VerificationMode
    ) async -> TimeEstimate? {
        guard totalBytes > 0, !destinationURLs.isEmpty else { return nil }

        // Get source read speed
        guard let readSpeed = await getReadSpeed(for: sourceURL), readSpeed > 0 else {
            return nil
        }

        // Get slowest destination write speed (bottleneck)
        var slowestWriteSpeed: Double = .infinity
        for destURL in destinationURLs {
            if let writeSpeed = await getWriteSpeed(for: destURL), writeSpeed > 0 {
                slowestWriteSpeed = min(slowestWriteSpeed, writeSpeed)
            }
        }
        guard slowestWriteSpeed < .infinity else { return nil }

        // Calculate copy time (limited by slower of read or write)
        let effectiveCopySpeed = min(readSpeed, slowestWriteSpeed)
        let copyTime = Double(totalBytes) / effectiveCopySpeed

        // Calculate verification time based on mode
        let verifyTime: Double
        switch verificationMode {
        case .quick:
            // No verification, just size check
            verifyTime = 0
        case .standard:
            // Read destination once for checksum
            verifyTime = Double(totalBytes) / slowestWriteSpeed
        case .thorough:
            // Read destination twice (SHA-256 + MD5)
            verifyTime = Double(totalBytes) / slowestWriteSpeed * 2
        case .paranoid:
            // Byte-by-byte comparison (read both source and destination)
            verifyTime = Double(totalBytes) / min(readSpeed, slowestWriteSpeed)
        }

        // Multiply by destination count (sequential copies)
        let totalCopyTime = copyTime * Double(destinationURLs.count)
        let totalVerifyTime = verifyTime * Double(destinationURLs.count)
        let totalTime = totalCopyTime + totalVerifyTime

        return TimeEstimate(
            totalSeconds: totalTime,
            copySeconds: totalCopyTime,
            verifySeconds: totalVerifyTime,
            readSpeedMBps: readSpeed / (1024 * 1024),
            writeSpeedMBps: slowestWriteSpeed / (1024 * 1024),
            destinationCount: destinationURLs.count
        )
    }

    // MARK: - Benchmark Implementation

    private func benchmarkRead(at url: URL) async -> Double? {
        // Find a file to read (prefer larger files for accuracy)
        guard let testFile = findTestFile(in: url) else { return nil }

        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: testFile.path),
              let fileSize = attributes[.size] as? Int64,
              fileSize > 0 else { return nil }

        // Read up to testSize bytes
        let bytesToRead = min(Int(fileSize), testSize)

        do {
            let handle = try FileHandle(forReadingFrom: testFile)
            defer { try? handle.close() }

            let start = CFAbsoluteTimeGetCurrent()
            _ = handle.readData(ofLength: bytesToRead)
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            guard elapsed > 0.001 else { return nil }  // Sanity check
            return Double(bytesToRead) / elapsed
        } catch {
            return nil
        }
    }

    private func benchmarkWrite(at url: URL) async -> Double? {
        let fm = FileManager.default
        let tempFile = url.appendingPathComponent(".bitmatch_benchmark_\(UUID().uuidString)")

        // Generate random data
        var randomData = Data(count: testSize)
        randomData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            arc4random_buf(baseAddress, testSize)
        }

        defer {
            try? fm.removeItem(at: tempFile)
        }

        do {
            let start = CFAbsoluteTimeGetCurrent()
            try randomData.write(to: tempFile, options: [.atomic])
            // Force sync to disk
            let handle = try FileHandle(forWritingTo: tempFile)
            try handle.synchronize()
            try handle.close()
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            guard elapsed > 0.001 else { return nil }
            return Double(testSize) / elapsed
        } catch {
            return nil
        }
    }

    private func findTestFile(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var bestFile: URL?
        var bestSize: Int64 = 0

        // Find a reasonably sized file (prefer 1MB-100MB range)
        var count = 0
        while let fileURL = enumerator.nextObject() as? URL, count < 100 {
            count += 1
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }

            let size64 = Int64(size)
            // Prefer files in 1-100MB range
            if size64 >= 1_000_000 && size64 <= 100_000_000 {
                if size64 > bestSize {
                    bestFile = fileURL
                    bestSize = size64
                }
            } else if bestFile == nil && size64 > 10_000 {
                // Fallback to any file > 10KB
                bestFile = fileURL
                bestSize = size64
            }
        }

        return bestFile
    }

    private func getVolumeID(for url: URL) -> String {
        // Get volume UUID or fall back to volume name
        if let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey]) {
            if let uuid = values.volumeUUIDString {
                return uuid
            }
            if let name = values.volumeName {
                return "name:\(name)"
            }
        }
        return "path:\(url.path)"
    }

    // MARK: - Cache Management

    func clearCache() {
        readSpeedCache.removeAll()
        writeSpeedCache.removeAll()
        cacheTimestamps.removeAll()
    }
}

// MARK: - Time Estimate Result

struct TimeEstimate {
    let totalSeconds: Double
    let copySeconds: Double
    let verifySeconds: Double
    let readSpeedMBps: Double
    let writeSpeedMBps: Double
    let destinationCount: Int

    var formatted: String {
        if totalSeconds < 60 {
            return "<1 min"
        } else if totalSeconds < 3600 {
            let minutes = Int(ceil(totalSeconds / 60))
            return "~\(minutes) min"
        } else {
            let hours = Int(totalSeconds / 3600)
            let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "~\(hours)h \(minutes)m"
            }
            return "~\(hours)h"
        }
    }

    var breakdown: String {
        let copyMin = Int(ceil(copySeconds / 60))
        let verifyMin = Int(ceil(verifySeconds / 60))
        if verifyMin > 0 {
            return "Copy: ~\(copyMin)m, Verify: ~\(verifyMin)m"
        }
        return "Copy: ~\(copyMin)m"
    }

    var speedSummary: String {
        let readStr = String(format: "%.0f", readSpeedMBps)
        let writeStr = String(format: "%.0f", writeSpeedMBps)
        return "Read: \(readStr) MB/s, Write: \(writeStr) MB/s"
    }
}
