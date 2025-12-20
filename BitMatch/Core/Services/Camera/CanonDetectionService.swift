// Core/Services/Camera/CanonDetectionService.swift
import Foundation

/// Specialized service for detecting Canon cameras via metadata and folder structure
final class CanonDetectionService {
    static let shared = CanonDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCanonCamera(at url: URL) -> String? {
        if let metadataInfo = checkCanonMetadata(at: url) {
            return metadataInfo
        }
        
        if let folderInfo = checkCanonFolderStructure(at: url) {
            return folderInfo
        }
        
        return nil
    }
    
    // MARK: - Canon Metadata Detection
    
    private func checkCanonMetadata(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Check for Canon-specific metadata files
        let canonMetadataFiles = [
            "MISC/CANON.INF",
            "MISC/CANONINF.DAT",
            "DCIM/CANONMSC/CANON.DAT"
        ]
        
        for metadataFile in canonMetadataFiles {
            let metadataPath = url.appendingPathComponent(metadataFile)
            
            if fm.fileExists(atPath: metadataPath.path) {
                if let cameraModel = extractCanonModelFromMetadata(metadataPath) {
                    return "Canon \(cameraModel)"
                }
                return "Canon"
            }
        }
        
        // Check CR2/CR3 files for metadata
        return checkCanonRAWFiles(at: url)
    }
    
    private func checkCanonRAWFiles(at url: URL) -> String? {
        let fm = FileManager.default
        let rawExtensions = ["CR2", "CR3", "CRW"]
        
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if rawExtensions.contains(fileURL.pathExtension.uppercased()) {
                    if let model = extractCanonModelFromRAW(fileURL) {
                        return "Canon \(model)"
                    }
                    return "Canon"
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Canon Folder Structure Detection
    
    private func checkCanonFolderStructure(at url: URL) -> String? {
        let fm = FileManager.default
        
        let canonIndicators = [
            "DCIM",
            "MISC",
            "PRIVATE/CANON",
            "CANONMSC"
        ]
        
        var foundIndicators = 0
        for indicator in canonIndicators {
            let indicatorPath = url.appendingPathComponent(indicator)
            if fm.fileExists(atPath: indicatorPath.path) {
                foundIndicators += 1
            }
        }
        
        // Check for Canon-specific DCIM folder patterns (e.g., 100CANON, 101CANON)
        let dcimPath = url.appendingPathComponent("DCIM")
        if fm.fileExists(atPath: dcimPath.path) {
            do {
                let dcimContents = try fm.contentsOfDirectory(atPath: dcimPath.path)
                for folder in dcimContents {
                    if folder.contains("CANON") || folder.range(of: "^[0-9]{3}CANON$", options: .regularExpression) != nil {
                        foundIndicators += 1
                        break
                    }
                }
            } catch {
                SharedLogger.debug("Could not read Canon DCIM contents: \(error.localizedDescription)", category: .transfer)
            }
        }
        
        return foundIndicators >= 2 ? "Canon" : nil
    }
    
    // MARK: - Metadata Extraction
    
    private func extractCanonModelFromMetadata(_ metadataPath: URL) -> String? {
        do {
            let metadataString = try String(contentsOf: metadataPath, encoding: .ascii)
            
            let canonModels = [
                "EOS R5": "R5",
                "EOS R6 Mark II": "R6 Mark II",
                "EOS R6": "R6",
                "EOS R8": "R8",
                "EOS R": "R",
                "EOS R10": "R10",
                "EOS R50": "R50",
                "5D Mark IV": "5D Mark IV",
                "5D4": "5D Mark IV",
                "1DX Mark III": "1DX Mark III",
                "90D": "90D",
                "80D": "80D",
                "M50 Mark II": "M50 Mark II",
                "M50": "M50",
                // Cinema/XF series
                "EOS C70": "C70",
                "C70": "C70",
                "EOS C300 Mark III": "C300 Mark III",
                "C300 Mark III": "C300 Mark III",
                "EOS C500 Mark II": "C500 Mark II",
                "C500 Mark II": "C500 Mark II",
                "XF605": "XF605",
                "XF705": "XF705"
            ]
            
            for (pattern, model) in canonModels {
                if metadataString.contains(pattern) {
                    return model
                }
            }

        } catch {
            SharedLogger.debug("Could not read Canon metadata file: \(error.localizedDescription)", category: .transfer)
        }
        
        return nil
    }
    
    private func extractCanonModelFromRAW(_ rawFile: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: rawFile) else { return nil }
        defer { try? fileHandle.close() }
        
        let headerSize = 2048
        guard let headerData = try? fileHandle.read(upToCount: headerSize) else { return nil }
        
        guard let headerString = String(data: headerData, encoding: .ascii) else { return nil }
        
        let canonModels = [
            "Canon EOS R5": "R5",
            "Canon EOS R6": "R6",
            "Canon EOS R": "R",
            "Canon EOS 5D Mark IV": "5D Mark IV",
            "Canon EOS-1D X Mark III": "1DX Mark III",
            "Canon EOS 90D": "90D",
            "Canon EOS 80D": "80D",
            "Canon EOS M50": "M50"
        ]
        
        for (pattern, model) in canonModels {
            if headerString.contains(pattern) {
                return model
            }
        }
        
        return nil
    }
}
