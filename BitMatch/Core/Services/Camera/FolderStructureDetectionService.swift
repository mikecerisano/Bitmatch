// Core/Services/Camera/FolderStructureDetectionService.swift
import Foundation

/// Service for detecting cameras based on folder structure patterns
final class FolderStructureDetectionService {
    static let shared = FolderStructureDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCameraFromStructure(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Get directory structure
        var foundFolders: [String] = []
        
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let folderURL as URL in enumerator {
                do {
                    let resourceValues = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == true {
                        // Get relative path from root
                        let relativePath = folderURL.path.replacingOccurrences(of: url.path + "/", with: "")
                        foundFolders.append(relativePath)
                    }
                } catch { }
            }
        }
        
        return analyzeStructurePatterns(foundFolders)
    }
    
    // MARK: - Structure Analysis
    
    private func analyzeStructurePatterns(_ folders: [String]) -> String? {
        let structurePatterns: [(patterns: [String], camera: String, requiredMatches: Int)] = [
            // Sony patterns
            (["PRIVATE/M4ROOT", "DCIM"], "Sony", 2),
            (["PRIVATE/AVCHD", "DCIM"], "Sony", 2),
            (["MP_ROOT", "DCIM"], "Sony", 2),
            
            // Canon patterns
            (["DCIM", "MISC"], "Canon", 2),
            (["PRIVATE/CANON", "DCIM"], "Canon", 2),
            (["CANONMSC", "DCIM"], "Canon", 2),
            
            // Panasonic patterns
            (["PRIVATE/PANASONIC", "DCIM"], "Panasonic", 2),
            (["PRIVATE/MISC", "DCIM"], "Panasonic", 2),
            
            // GoPro patterns
            (["DCIM/100GOPRO"], "GoPro", 1),
            (["DCIM/101GOPRO"], "GoPro", 1),
            (["MISC"], "GoPro", 1),
            
            // Blackmagic patterns
            (["Blackmagic RAW"], "Blackmagic", 1),
            (["BRAW"], "Blackmagic", 1),
            
            // RED patterns
            (["RED_RAW"], "RED", 1),
            (["R3D"], "RED", 1),
            
            // DJI patterns
            (["DCIM/100MEDIA"], "DJI", 1),
            (["DCIM/101MEDIA"], "DJI", 1),
            
            // Professional camera patterns
            (["CLIPS"], "Professional", 1),
            (["CONTENTS"], "Professional", 1),
            (["PROAV"], "Professional", 1),
            
            // Generic camera patterns (lower priority)
            (["DCIM"], "Generic", 1)
        ]
        
        for (patterns, camera, requiredMatches) in structurePatterns {
            var matchCount = 0
            
            for pattern in patterns {
                if folders.contains(where: { $0.contains(pattern) }) {
                    matchCount += 1
                }
            }
            
            if matchCount >= requiredMatches {
                return camera
            }
        }
        
        // Check for numbered DCIM folders (common camera pattern)
        let dcimPattern = folders.filter { $0.range(of: "^DCIM/[0-9]{3}[A-Z]+$", options: .regularExpression) != nil }
        if !dcimPattern.isEmpty {
            return "Generic"
        }
        
        return nil
    }
}

