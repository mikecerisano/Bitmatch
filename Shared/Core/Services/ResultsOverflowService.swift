// ResultsOverflowService.swift - Disk overflow for large transfer results
import Foundation

/// Service that manages disk overflow for large transfer result sets.
/// Keeps recent results in memory while spilling older results to disk
/// to prevent memory bloat during very large transfers.
actor ResultsOverflowService {

    // MARK: - Configuration
    private let maxInMemoryResults: Int
    private let operationId: UUID

    // MARK: - State
    private var inMemoryResults: [ResultRow] = []
    private var overflowFileURL: URL?
    private var overflowCount: Int = 0
    private var overflowFileHandle: FileHandle?

    // MARK: - Initialization

    init(operationId: UUID, maxInMemoryResults: Int = 5_000) {
        self.operationId = operationId
        self.maxInMemoryResults = maxInMemoryResults
    }

    deinit {
        // Clean up any open file handle
        try? overflowFileHandle?.close()
    }

    // MARK: - Public API

    /// Add a result row, spilling to disk if memory limit is exceeded
    func addResult(_ result: ResultRow) {
        if inMemoryResults.count >= maxInMemoryResults {
            // Spill oldest result to disk before adding new one
            if let oldest = inMemoryResults.first {
                spillToDisk(oldest)
                inMemoryResults.removeFirst()
            }
        }
        inMemoryResults.append(result)
    }

    /// Add multiple results
    func addResults(_ results: [ResultRow]) {
        for result in results {
            addResult(result)
        }
    }

    /// Update an existing result in memory (returns false if not found in memory)
    func updateResult(matching path: String, destination: String, with updated: ResultRow) -> Bool {
        if let idx = inMemoryResults.firstIndex(where: { $0.path == path && $0.destination == destination }) {
            inMemoryResults[idx] = updated
            return true
        }
        // Result might be in overflow file - we don't update those (they're already written)
        return false
    }

    /// Get current in-memory results (for UI display)
    var currentResults: [ResultRow] {
        return inMemoryResults
    }

    /// Get total count (in-memory + overflow)
    var totalCount: Int {
        return inMemoryResults.count + overflowCount
    }

    /// Get all results (in-memory + overflow from disk) for report generation
    func getAllResults() async -> [ResultRow] {
        var allResults: [ResultRow] = []

        // First, read overflow from disk
        if let overflowURL = overflowFileURL, overflowCount > 0 {
            closeOverflowFile()
            if let overflowResults = readOverflowFromDisk(url: overflowURL) {
                allResults.append(contentsOf: overflowResults)
            }
        }

        // Then append in-memory results (these are the most recent)
        allResults.append(contentsOf: inMemoryResults)

        return allResults
    }

    /// Clear all results and delete overflow file
    func clear() {
        inMemoryResults.removeAll()
        closeOverflowFile()
        deleteOverflowFile()
        overflowCount = 0
    }

    // MARK: - Private Helpers

    private func spillToDisk(_ result: ResultRow) {
        // Lazily create overflow file
        if overflowFileURL == nil {
            createOverflowFile()
        }

        guard let handle = overflowFileHandle else {
            SharedLogger.error("Failed to write overflow result - no file handle", category: .transfer)
            return
        }

        // Encode result as JSON line
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(result)
            // Write as newline-delimited JSON
            var lineData = data
            lineData.append(contentsOf: "\n".utf8)
            try handle.write(contentsOf: lineData)
            overflowCount += 1
        } catch {
            SharedLogger.error("Failed to encode overflow result: \(error)", category: .transfer)
        }
    }

    private func createOverflowFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "bitmatch_results_overflow_\(operationId.uuidString).jsonl"
        let url = tempDir.appendingPathComponent(fileName)

        do {
            // Create empty file
            FileManager.default.createFile(atPath: url.path, contents: nil)
            overflowFileHandle = try FileHandle(forWritingTo: url)
            overflowFileURL = url
            SharedLogger.debug("Created overflow file: \(url.path)", category: .transfer)
        } catch {
            SharedLogger.error("Failed to create overflow file: \(error)", category: .transfer)
        }
    }

    private func closeOverflowFile() {
        do {
            try overflowFileHandle?.synchronize()
            try overflowFileHandle?.close()
        } catch {
            SharedLogger.debug("Error closing overflow file: \(error)", category: .transfer)
        }
        overflowFileHandle = nil
    }

    private func readOverflowFromDisk(url: URL) -> [ResultRow]? {
        do {
            let data = try Data(contentsOf: url)
            let lines = data.split(separator: UInt8(ascii: "\n"))

            let decoder = JSONDecoder()
            var results: [ResultRow] = []
            results.reserveCapacity(overflowCount)

            for line in lines {
                if let result = try? decoder.decode(ResultRow.self, from: Data(line)) {
                    results.append(result)
                }
            }

            SharedLogger.debug("Read \(results.count) results from overflow file", category: .transfer)
            return results
        } catch {
            SharedLogger.error("Failed to read overflow file: \(error)", category: .transfer)
            return nil
        }
    }

    private func deleteOverflowFile() {
        guard let url = overflowFileURL else { return }
        do {
            try FileManager.default.removeItem(at: url)
            SharedLogger.debug("Deleted overflow file: \(url.path)", category: .transfer)
        } catch {
            SharedLogger.debug("Failed to delete overflow file: \(error)", category: .transfer)
        }
        overflowFileURL = nil
    }
}

// MARK: - ResultRow Codable Extension

extension ResultRow: Codable {
    enum CodingKeys: String, CodingKey {
        case id, path, status, size, checksum, destination, destinationPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let path = try container.decode(String.self, forKey: .path)
        let status = try container.decode(String.self, forKey: .status)
        let size = try container.decode(Int64.self, forKey: .size)
        let checksum = try container.decodeIfPresent(String.self, forKey: .checksum)
        let destination = try container.decodeIfPresent(String.self, forKey: .destination)
        let destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath)

        self.init(id: id, path: path, status: status, size: size, checksum: checksum, destination: destination, destinationPath: destinationPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(status, forKey: .status)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(checksum, forKey: .checksum)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encodeIfPresent(destinationPath, forKey: .destinationPath)
    }
}
