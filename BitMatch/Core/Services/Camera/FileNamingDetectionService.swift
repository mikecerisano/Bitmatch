// Core/Services/Camera/FileNamingDetectionService.swift
import Foundation

/// Service for detecting cameras based on file naming patterns
final class FileNamingDetectionService {
    static let shared = FileNamingDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCameraFromNaming(at url: URL) -> String? {
        let fm = FileManager.default
        var sampleFiles: [String] = []
        
        // Collect sample filenames for pattern analysis
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let filename = fileURL.lastPathComponent
                sampleFiles.append(filename)
                
                if sampleFiles.count >= 20 { break } // Analyze a reasonable sample
            }
        }
        
        return analyzFileNamingPatterns(sampleFiles)
    }
    
    // MARK: - Pattern Analysis
    
    private func analyzFileNamingPatterns(_ filenames: [String]) -> String? {
        let patterns: [(pattern: String, camera: String)] = [
            // GoPro patterns
            ("^GH[0-9]{6}\\.", "GoPro"),
            ("^GOPR[0-9]{4}\\.", "GoPro"),
            ("^GP[0-9]{6}\\.", "GoPro"),
            
            // Canon patterns
            ("^IMG_[0-9]{4}\\.(CR2|CR3|JPG)", "Canon"),
            ("^MVI_[0-9]{4}\\.MOV", "Canon"),
            ("^_MG_[0-9]{4}\\.", "Canon"),
            
            // Sony patterns
            ("^DSC[0-9]{5}\\.", "Sony"),
            ("^_DSC[0-9]{4}\\.", "Sony"),
            ("^C[0-9]{4}\\.(MP4|MTS)", "Sony"),
            
            // Nikon patterns
            ("^DSC_[0-9]{4}\\.", "Nikon"),
            ("^_DSC[0-9]{4}\\.NEF", "Nikon"),
            
            // Fujifilm patterns
            ("^DSCF[0-9]{4}\\.(RAF|JPG)", "Fujifilm"),
            ("^_T[0-9]{6}\\.", "Fujifilm"),
            
            // Panasonic patterns
            ("^P[0-9]{7}\\.", "Panasonic"),
            ("^_P[0-9]{6}\\.", "Panasonic"),
            
            // Blackmagic patterns
            ("^[A-Z]{1}[0-9]{3}C[0-9]{4}_[0-9]{6}_[A-Z]{4}\\.", "Blackmagic"),
            
            // RED patterns
            ("^[A-Z]{1}[0-9]{3}_C[0-9]{3}_[0-9]{4}[A-Z]{2}\\.", "RED"),
            ("^[A-Z]+_[0-9]+\\.R3D", "RED"),
            
            // ARRI patterns
            ("^[A-Z]{1}[0-9]{3}C[0-9]{3}_[0-9]{4}[A-Z]{2}_[A-Z]{4}\\.", "ARRI"),
            
            // DJI patterns
            ("^DJI_[0-9]{4}\\.(MP4|MOV)", "DJI"),
            ("^DJIG[0-9]{4}\\.", "DJI"),
            
            // iPhone patterns
            ("^IMG_[0-9]{4}\\.(HEIC|MOV)", "iPhone"),
            ("^VID_[0-9]{8}_[0-9]{6}\\.", "iPhone")
        ]
        
        var patternMatches: [String: Int] = [:]
        
        for filename in filenames {
            for (pattern, camera) in patterns {
                if filename.range(of: pattern, options: .regularExpression) != nil {
                    patternMatches[camera, default: 0] += 1
                }
            }
        }
        
        // Return the camera with the most pattern matches
        if let bestMatch = patternMatches.max(by: { $0.value < $1.value }) {
            // Require at least 3 matches to be confident
            return bestMatch.value >= 3 ? bestMatch.key : nil
        }
        
        return nil
    }
}