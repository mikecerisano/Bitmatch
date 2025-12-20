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
            if !prefs.production.isEmpty || !prefs.clientName.isEmpty || !prefs.company.isEmpty {
                return MHLGenerator.MHLFile.ProductionInfo(
                    title: prefs.production,
                    client: prefs.clientName,
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
            SharedLogger.warning("MHL validation issues: \(issues.joined(separator: ", "))", category: .transfer)
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
        
        // Use the real checksum service for industry-standard verification
        let checksumService = SharedChecksumService.shared
        let checksum = try await checksumService.generateChecksum(
            for: url,
            type: algorithm,
            progressCallback: { progress, status in
                // Progress is handled at higher level for now
                SharedLogger.debug("Checksum progress for \(url.lastPathComponent): \(Int(progress * 100))%", category: .transfer)
            }
        )
        
        await collector.addEntry(url: url, hash: checksum, size: Int64(fileSize))
    }
}