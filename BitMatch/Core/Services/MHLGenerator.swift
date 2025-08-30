// Core/Services/MHLGenerator.swift
import Foundation
import CryptoKit

/// Generates MHL (Media Hash List) files for Netflix and professional delivery requirements
final class MHLGenerator {
    
    // MARK: - MHL File Structure
    struct MHLFile {
        let version: String = "2.0"
        let creator: String = "BitMatch"
        let creatorVersion: String
        let jobID: UUID
        let sourceFolder: String
        let destinationFolder: String
        let hashAlgorithm: ChecksumAlgorithm
        let files: [MHLEntry]
        let creationDate: Date
        let completionDate: Date
        let productionInfo: ProductionInfo?
        
        struct MHLEntry {
            let relativePath: String
            let size: Int64
            let hash: String
            let verificationDate: Date
            let status: VerificationStatus
            
            enum VerificationStatus: String {
                case verified = "verified"
                case failed = "failed"
                case generated = "generated"
            }
        }
        
        struct ProductionInfo {
            let title: String
            let client: String
            let company: String
        }
    }
    
    // MARK: - Generate MHL during verification
    static func generateMHL(
        for verifiedFiles: [(url: URL, hash: String, size: Int64)],
        sourceURL: URL,
        destinationURL: URL,
        algorithm: ChecksumAlgorithm,
        jobID: UUID,
        startTime: Date,
        productionInfo: MHLFile.ProductionInfo? = nil
    ) throws -> URL {
        
        // Create MHL entries from verified files
        let entries = verifiedFiles.map { file in
            MHLFile.MHLEntry(
                relativePath: file.url.relativePath(to: destinationURL),
                size: file.size,
                hash: file.hash,
                verificationDate: Date(),
                status: .verified
            )
        }
        
        // Get app version
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        // Create MHL structure
        let mhl = MHLFile(
            creatorVersion: appVersion,
            jobID: jobID,
            sourceFolder: sourceURL.lastPathComponent,
            destinationFolder: destinationURL.lastPathComponent,
            hashAlgorithm: algorithm,
            files: entries,
            creationDate: startTime,
            completionDate: Date(),
            productionInfo: productionInfo
        )
        
        // Generate XML
        let xmlContent = generateXML(from: mhl)
        
        // Save MHL file
        let mhlFileName = generateMHLFileName(for: destinationURL, jobID: jobID)
        let mhlURL = destinationURL.appendingPathComponent(mhlFileName)
        
        try xmlContent.write(to: mhlURL, atomically: true, encoding: .utf8)
        
        // Also save a companion .mhl.md5 file (some systems expect this)
        try generateCompanionChecksum(for: mhlURL)
        
        return mhlURL
    }
    
    // MARK: - Generate MHL from existing results
    static func generateMHLFromResults(
        results: [ResultRow],
        sourceURL: URL,
        destinationURL: URL,
        algorithm: ChecksumAlgorithm,
        jobID: UUID,
        startTime: Date,
        prefs: ReportPrefs
    ) async throws -> URL {
        
        // Filter for matched files only
        let matchedResults = results.filter { $0.status == .match }
        
        // Collect checksums for matched files
        var verifiedFiles: [(url: URL, hash: String, size: Int64)] = []
        
        for result in matchedResults {
            guard let targetPath = result.target else { continue }
            let fileURL = URL(fileURLWithPath: targetPath)
            
            // Get file size
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            
            // Calculate checksum (using existing function)
            let hash = try await withChecksumGate {
                try FileOperationsService.computeChecksum(for: fileURL, algorithm: algorithm)
            }
            
            verifiedFiles.append((url: fileURL, hash: hash, size: Int64(size)))
        }
        
        // Create production info if available
        let productionInfo: MHLFile.ProductionInfo? = {
            if !prefs.projectName.isEmpty || !prefs.clientName.isEmpty {
                return MHLFile.ProductionInfo(
                    title: prefs.projectName,
                    client: prefs.clientName,
                    company: prefs.clientName // Use clientName for company as well
                )
            }
            return nil
        }()
        
        return try generateMHL(
            for: verifiedFiles,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            algorithm: algorithm,
            jobID: jobID,
            startTime: startTime,
            productionInfo: productionInfo
        )
    }
    
    // MARK: - XML Generation
    private static func generateXML(from mhl: MHLFile) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="\(mhl.version)">
          <creatorinfo>
            <name>\(mhl.creator)</name>
            <version>\(mhl.creatorVersion)</version>
            <creationdate>\(dateFormatter.string(from: mhl.creationDate))</creationdate>
            <finishdate>\(dateFormatter.string(from: mhl.completionDate))</finishdate>
            <jobid>\(mhl.jobID.uuidString)</jobid>
        """
        
        // Add production info if available
        if let production = mhl.productionInfo {
            xml += """
            
            <production>
        """
            if !production.title.isEmpty {
                xml += """
                
              <title>\(escapeXML(production.title))</title>
        """
            }
            if !production.client.isEmpty {
                xml += """
                
              <client>\(escapeXML(production.client))</client>
        """
            }
            if !production.company.isEmpty {
                xml += """
                
              <company>\(escapeXML(production.company))</company>
        """
            }
            xml += """
            
            </production>
        """
        }
        
        xml += """
        
          </creatorinfo>
          <source>\(escapeXML(mhl.sourceFolder))</source>
          <destination>\(escapeXML(mhl.destinationFolder))</destination>
          <hashalgorithm>\(mhl.hashAlgorithm.rawValue.lowercased())</hashalgorithm>
          <hashes>
        """
        
        // Add file entries
        for entry in mhl.files {
            xml += """
            
            <hash>
              <file>\(escapeXML(entry.relativePath))</file>
              <size>\(entry.size)</size>
              <\(mhl.hashAlgorithm.rawValue.lowercased())>\(entry.hash)</\(mhl.hashAlgorithm.rawValue.lowercased())>
              <hashdate>\(dateFormatter.string(from: entry.verificationDate))</hashdate>
              <status>\(entry.status.rawValue)</status>
            </hash>
        """
        }
        
        xml += """
        
          </hashes>
        </hashlist>
        """
        
        return xml
    }
    
    // MARK: - Helper Functions
    
    private static func generateMHLFileName(for destination: URL, jobID: UUID) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Use folder name in the MHL filename for clarity
        let folderName = destination.lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        
        return "\(folderName)_\(timestamp).mhl"
    }
    
    private static func generateCompanionChecksum(for mhlURL: URL) throws {
        // Some systems expect a .mhl.md5 file containing the checksum of the MHL itself
        let mhlData = try Data(contentsOf: mhlURL)
        let hash = Insecure.MD5.hash(data: mhlData)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        let companionURL = mhlURL.appendingPathExtension("md5")
        let content = "\(hashString)  \(mhlURL.lastPathComponent)\n"
        try content.write(to: companionURL, atomically: true, encoding: .utf8)
    }
    
    private static func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    // MARK: - Validate existing MHL
    static func validateMHL(at url: URL) throws -> Bool {
        let content = try String(contentsOf: url, encoding: .utf8)
        
        // Basic validation - check for required elements
        let requiredElements = ["<hashlist", "<creatorinfo>", "<hashes>", "</hashlist>"]
        for element in requiredElements {
            if !content.contains(element) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Parse existing MHL (for verification)
    static func parseMHL(at url: URL) throws -> MHLFile? {
        // This would parse an existing MHL file - useful for re-verification
        // For now, returning nil as full parsing isn't needed yet
        return nil
    }
}

// MARK: - Integration with File Operations
extension MHLGenerator {
    
    /// Collects checksums during verification for MHL generation
    struct MHLCollector {
        private var entries: [(url: URL, hash: String, size: Int64)] = []
        private let lock = NSLock()
        
        mutating func addEntry(url: URL, hash: String, size: Int64) {
            lock.lock()
            defer { lock.unlock() }
            entries.append((url: url, hash: hash, size: size))
        }
        
        func getEntries() -> [(url: URL, hash: String, size: Int64)] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }
}

// MARK: - Netflix-specific validations
extension MHLGenerator {
    
    /// Validates that MHL meets Netflix delivery requirements
    static func validateForNetflix(mhlURL: URL) throws -> (valid: Bool, issues: [String]) {
        var issues: [String] = []
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: mhlURL.path) else {
            return (false, ["MHL file not found"])
        }
        
        // Check file extension
        if mhlURL.pathExtension.lowercased() != "mhl" {
            issues.append("File must have .mhl extension")
        }
        
        // Parse and validate content
        let content = try String(contentsOf: mhlURL, encoding: .utf8)
        
        // Netflix requires SHA-256 or MD5
        if !content.contains("<sha256>") && !content.contains("<md5>") {
            issues.append("Netflix requires SHA-256 or MD5 checksums")
        }
        
        // Check for required metadata
        if !content.contains("<creationdate>") {
            issues.append("Missing creation date")
        }
        
        if !content.contains("<source>") || !content.contains("<destination>") {
            issues.append("Missing source/destination information")
        }
        
        return (issues.isEmpty, issues)
    }
}
