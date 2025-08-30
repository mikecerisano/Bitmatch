// Core/Services/MHLOperationService.swift
import Foundation

/// Service for handling MHL generation during verification operations
final class MHLOperationService {
    
    // MARK: - MHL Collection
    
    /// Thread-safe collector for MHL entries during verification
    actor MHLCollectorActor {
        private var entries: [(url: URL, hash: String, size: Int64)] = []
        
        func addEntry(url: URL, hash: String, size: Int64) {
            entries.append((url: url, hash: hash, size: size))
        }
        
        func getEntries() -> [(url: URL, hash: String, size: Int64)] {
            return entries
        }
        
        func clear() {
            entries.removeAll()
        }
    }
    
    // MARK: - MHL Generation
    
    @MainActor
    static func generateMHLFile(
        from collector: [(url: URL, hash: String, size: Int64)],
        source: URL,
        destination: URL,
        algorithm: ChecksumAlgorithm,
        jobID: UUID,
        jobStart: Date,
        settingsViewModel: SettingsViewModel,
        onProgress: @escaping (String) -> Void
    ) async throws -> (success: Bool, filename: String?) {
        
        onProgress("Generating MHL file...")
        
        // Create production info if available
        let productionInfo: MHLGenerator.MHLFile.ProductionInfo? = {
            let prefs = settingsViewModel.prefs
            if !prefs.production.isEmpty || !prefs.client.isEmpty || !prefs.company.isEmpty {
                return MHLGenerator.MHLFile.ProductionInfo(
                    title: prefs.production,
                    client: prefs.client,
                    company: prefs.company
                )
            }
            return nil
        }()
        
        // Generate MHL
        let mhlURL = try MHLGenerator.generateMHL(
            for: collector,
            sourceURL: source,
            destinationURL: destination,
            algorithm: algorithm,
            jobID: jobID,
            startTime: jobStart,
            productionInfo: productionInfo
        )
        
        // Validate for Netflix if needed
        let (valid, issues) = try MHLGenerator.validateForNetflix(mhlURL: mhlURL)
        if !valid && !issues.isEmpty {
            print("MHL validation issues: \(issues.joined(separator: ", "))")
        }
        
        onProgress("MHL file generated: \(mhlURL.lastPathComponent)")
        
        return (success: true, filename: mhlURL.lastPathComponent)
    }
    
    // MARK: - Helper Methods
    
    static func shouldGenerateMHL(for verificationMode: VerificationMode) -> Bool {
        return verificationMode.requiresMHL
    }
    
    static func collectMHLEntry(
        for url: URL,
        algorithm: ChecksumAlgorithm,
        collector: MHLCollectorActor
    ) async throws {
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let checksum = try await FileOperationsService.computeChecksumWithCache(
            for: url,
            algorithm: algorithm
        )
        await collector.addEntry(url: url, hash: checksum, size: Int64(fileSize))
    }
}