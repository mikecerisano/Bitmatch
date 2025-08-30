// Core/Services/Camera/PanasonicDetectionService.swift
import Foundation

/// Specialized service for detecting Panasonic cameras via metadata and folder structure
final class PanasonicDetectionService {
    static let shared = PanasonicDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectPanasonicCamera(at url: URL) -> String? {
        if let metadataInfo = checkPanasonicMetadata(at: url) {
            return metadataInfo
        }
        
        if let folderInfo = checkPanasonicFolderStructure(at: url) {
            return folderInfo
        }
        
        return nil
    }
    
    // MARK: - Panasonic Metadata Detection
    
    private func checkPanasonicMetadata(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Check for Panasonic-specific metadata files
        let panasonicMetadataFiles = [
            "PRIVATE/PANASONIC/MISC/DPOF.DAT",
            "MISC/PANASONIC.DAT",
            "PRIVATE/MISC/INFO.DAT"
        ]
        
        for metadataFile in panasonicMetadataFiles {
            let metadataPath = url.appendingPathComponent(metadataFile)
            
            if fm.fileExists(atPath: metadataPath.path) {
                if let cameraModel = extractPanasonicModelFromMetadata(metadataPath) {
                    return "Panasonic \(cameraModel)"
                }
                return "Panasonic"
            }
        }
        
        // Check RW2/RAF files for metadata
        return checkPanasonicRAWFiles(at: url)
    }
    
    private func checkPanasonicRAWFiles(at url: URL) -> String? {
        let fm = FileManager.default
        let rawExtensions = ["RW2", "RAW"]
        
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if rawExtensions.contains(fileURL.pathExtension.uppercased()) {
                    if let model = extractPanasonicModelFromRAW(fileURL) {
                        return "Panasonic \(model)"
                    }
                    return "Panasonic"
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Panasonic Folder Structure Detection
    
    private func checkPanasonicFolderStructure(at url: URL) -> String? {
        let fm = FileManager.default
        
        let panasonicIndicators = [
            "DCIM",
            "MISC",
            "PRIVATE/PANASONIC",
            "PRIVATE/MISC"
        ]
        
        var foundIndicators = 0
        for indicator in panasonicIndicators {
            let indicatorPath = url.appendingPathComponent(indicator)
            if fm.fileExists(atPath: indicatorPath.path) {
                foundIndicators += 1
            }
        }
        
        // Check for Panasonic-specific DCIM folder patterns (e.g., 100_PANA)
        let dcimPath = url.appendingPathComponent("DCIM")
        if fm.fileExists(atPath: dcimPath.path) {
            do {
                let dcimContents = try fm.contentsOfDirectory(atPath: dcimPath.path)
                for folder in dcimContents {
                    if folder.contains("PANA") || folder.range(of: "^[0-9]{3}_PANA$", options: .regularExpression) != nil {
                        foundIndicators += 1
                        break
                    }
                }
            } catch { }
        }
        
        return foundIndicators >= 2 ? "Panasonic" : nil
    }
    
    // MARK: - Metadata Extraction
    
    private func extractPanasonicModelFromMetadata(_ metadataPath: URL) -> String? {
        do {
            let metadataData = try Data(contentsOf: metadataPath)
            guard let metadataString = String(data: metadataData, encoding: .ascii) ?? String(data: metadataData, encoding: .utf8) else { return nil }
            
            let panasonicModels = [
                "DC-GH6": "GH6",
                "DC-GH5S": "GH5S",
                "DC-GH5": "GH5",
                "DC-G9": "G9",
                "DC-S1H": "S1H",
                "DC-S1R": "S1R",
                "DC-S1": "S1",
                "DC-S5": "S5",
                "DC-FZ2500": "FZ2500",
                "DC-FZ1000": "FZ1000",
                "DMC-GH4": "GH4",
                "DMC-GH3": "GH3",
                "DMC-G7": "G7",
                "DMC-G85": "G85"
            ]
            
            for (pattern, model) in panasonicModels {
                if metadataString.contains(pattern) {
                    return model
                }
            }
            
        } catch { }
        
        return nil
    }
    
    private func extractPanasonicModelFromRAW(_ rawFile: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: rawFile) else { return nil }
        defer { try? fileHandle.close() }
        
        let headerSize = 2048
        guard let headerData = try? fileHandle.read(upToCount: headerSize) else { return nil }
        
        guard let headerString = String(data: headerData, encoding: .ascii) else { return nil }
        
        let panasonicModels = [
            "PANASONIC": "",
            "DC-GH6": "GH6",
            "DC-GH5": "GH5",
            "DC-S1H": "S1H",
            "DC-S5": "S5"
        ]
        
        for (pattern, model) in panasonicModels {
            if headerString.contains(pattern) {
                return model.isEmpty ? nil : model
            }
        }
        
        return nil
    }
}

