import Foundation

/// Manages persistent state for operations to allow recovery/resume
final class OperationStateManager {
    
    private static let stateDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stateDir = appSupport.appendingPathComponent("BitMatch/States", isDirectory: true)
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        return stateDir
    }()
    
    // MARK: - State Persistence Models
    struct PersistedOperation: Codable {
        let id: UUID
        let startTime: Date
        let mode: String  // AppMode as string
        let sourceURL: URL
        let destinationURLs: [URL]
        let verificationMode: String
        let lastProcessedFile: String?
        let processedCount: Int
        let totalCount: Int
        let checkpoints: [Checkpoint]
        
        struct Checkpoint: Codable {
            let timestamp: Date
            let processedCount: Int
            let lastFile: String
        }
    }
    
    // MARK: - Save State
    static func saveState(_ operation: PersistedOperation) {
        let stateFile = stateDirectory.appendingPathComponent("\(operation.id.uuidString).json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(operation)
            try data.write(to: stateFile)
        } catch {
            SharedLogger.error("Failed to save operation state: \(error)")
        }
        // Note: Shared OperationStateService mirroring removed to avoid actor crossing
    }
    
    // MARK: - Load State
    static func loadState(for id: UUID) -> PersistedOperation? {
        let stateFile = stateDirectory.appendingPathComponent("\(id.uuidString).json")
        
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: stateFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return try decoder.decode(PersistedOperation.self, from: data)
        } catch {
            SharedLogger.error("Failed to load operation state: \(error)")
            return nil
        }
    }
    
    // MARK: - Check for Interrupted Operations
    static func checkForInterruptedOperations() -> [PersistedOperation] {
        var interrupted: [PersistedOperation] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: stateDirectory,
                                                                   includingPropertiesForKeys: [.creationDateKey])
            
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let operation = try? JSONDecoder().decode(PersistedOperation.self, from: data) {
                    
                    // Consider operations older than 1 hour as potentially interrupted
                    let age = Date().timeIntervalSince(operation.startTime)
                    if age > 3600 && operation.processedCount < operation.totalCount {
                        interrupted.append(operation)
                    }
                }
            }
        } catch {
            SharedLogger.error("Failed to check for interrupted operations: \(error)")
        }
        
        return interrupted
    }
    
    // MARK: - Clear State
    static func clearState(for id: UUID) {
        let stateFile = stateDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: stateFile)
    }
    
    // MARK: - Get Operation
    static func getOperation(for id: UUID) -> PersistedOperation? {
        return loadState(for: id)
    }
    
    // MARK: - Clear Old States
    static func clearOldStates(olderThan days: Int = 7) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: stateDirectory,
                                                                   includingPropertiesForKeys: [.creationDateKey])
            
            let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 3600))
            
            for file in files {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   creationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            SharedLogger.error("Failed to clear old states: \(error)")
        }
    }
    
    // MARK: - Create Checkpoint
    static func createCheckpoint(for operationID: UUID, filesProcessed: Int, lastFile: String) {
        if let operation = loadState(for: operationID) {
            let checkpoint = PersistedOperation.Checkpoint(
                timestamp: Date(),
                processedCount: filesProcessed,
                lastFile: lastFile
            )
            
            var checkpoints = operation.checkpoints
            checkpoints.append(checkpoint)
            
            // Keep only last 10 checkpoints
            if checkpoints.count > 10 {
                checkpoints = Array(checkpoints.suffix(10))
            }
            
            let updated = PersistedOperation(
                id: operation.id,
                startTime: operation.startTime,
                mode: operation.mode,
                sourceURL: operation.sourceURL,
                destinationURLs: operation.destinationURLs,
                verificationMode: operation.verificationMode,
                lastProcessedFile: lastFile,
                processedCount: filesProcessed,
                totalCount: operation.totalCount,
                checkpoints: checkpoints
            )
            
            saveState(updated)
        }
    }
}

// MARK: - Resume Support Extension
extension OperationStateManager {
    
    struct ResumeInfo {
        let operation: PersistedOperation
        let shouldResume: Bool
        let estimatedProgress: Double
    }
    
    static func getResumeInfo() -> ResumeInfo? {
        let candidates = checkForInterruptedOperations()
        guard let mostRecent = candidates.max(by: { $0.startTime < $1.startTime }) else { return nil }
        let progress = Double(mostRecent.processedCount) / Double(max(1, mostRecent.totalCount))
        return ResumeInfo(operation: mostRecent, shouldResume: progress > 0.1 && progress < 0.95, estimatedProgress: progress)
    }
}
