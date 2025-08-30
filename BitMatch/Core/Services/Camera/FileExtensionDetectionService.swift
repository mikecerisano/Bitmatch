// Core/Services/Camera/FileExtensionDetectionService.swift
import Foundation

/// Service for detecting cameras based on file extension patterns
final class FileExtensionDetectionService {
    static let shared = FileExtensionDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCameraFromExtensions(at url: URL) -> String? {
        let fm = FileManager.default
        var extensionCounts: [String: Int] = [:]
        
        // Count file extensions
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.uppercased()
                if !ext.isEmpty {
                    extensionCounts[ext, default: 0] += 1
                }
            }
        }
        
        return analyzeExtensionPatterns(extensionCounts)
    }
    
    // MARK: - Extension Analysis
    
    private func analyzeExtensionPatterns(_ extensionCounts: [String: Int]) -> String? {
        let extensionMappings: [String: (camera: String, weight: Int)] = [
            // Camera-specific RAW formats
            "RAF": ("Fujifilm", 10),
            "CR2": ("Canon", 10),
            "CR3": ("Canon", 10),
            "NEF": ("Nikon", 10),
            "RW2": ("Panasonic", 10),
            "ARW": ("Sony", 10),
            "ORF": ("Olympus", 10),
            "DNG": ("Generic", 5),
            
            // Video formats with brand associations
            "R3D": ("RED", 10),
            "BRAW": ("Blackmagic", 10),
            "MXF": ("Professional", 8),
            "MTS": ("Sony", 6),
            "AVCHD": ("Sony", 8),
            "M2TS": ("Panasonic", 6),
            
            // Common but less specific
            "MOV": ("Generic", 2),
            "MP4": ("Generic", 2),
            "AVI": ("Generic", 1),
            "MKV": ("Generic", 1),
            
            // Image formats
            "HEIC": ("iPhone", 8),
            "JPG": ("Generic", 1),
            "JPEG": ("Generic", 1),
            "TIFF": ("Professional", 3),
            "TIF": ("Professional", 3)
        ]
        
        var cameraScores: [String: Int] = [:]
        
        for (ext, count) in extensionCounts {
            if let mapping = extensionMappings[ext] {
                let score = count * mapping.weight
                cameraScores[mapping.camera, default: 0] += score
            }
        }
        
        // Require minimum threshold and avoid generic matches unless dominant
        if let bestMatch = cameraScores.max(by: { $0.value < $1.value }) {
            // Higher threshold for generic cameras
            let minScore = bestMatch.key == "Generic" ? 20 : 10
            return bestMatch.value >= minScore ? bestMatch.key : nil
        }
        
        return nil
    }
}