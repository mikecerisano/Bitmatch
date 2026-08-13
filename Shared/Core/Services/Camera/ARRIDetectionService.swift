// Core/Services/Camera/ARRIDetectionService.swift
import Foundation

/// Specialized service for detecting ARRI cameras via ALE files and metadata
final class ARRIDetectionService {
    static let shared = ARRIDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectARRICamera(at url: URL) -> String? {
        return checkForALEFile(at: url)
    }
    
    // MARK: - ALE File Detection
    
    private func checkForALEFile(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Look for .ale files in the directory tree
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "ale" {
                    return extractCameraFromALE(aleFile: fileURL)
                }
            }
        }
        
        return nil
    }
    
    private func extractCameraFromALE(aleFile: URL) -> String? {
        do {
            let aleContent = try String(contentsOf: aleFile, encoding: .utf8)
            let lines = aleContent.components(separatedBy: .newlines)
            
            // Look for camera information in ALE metadata
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                // Check for ARRI camera models in metadata
                if trimmedLine.contains("ALEXA") {
                    if trimmedLine.contains("MINI LF") {
                        return "ARRI Alexa Mini LF"
                    } else if trimmedLine.contains("MINI") {
                        return "ARRI Alexa Mini"
                    } else if trimmedLine.contains("LF") {
                        return "ARRI Alexa LF"
                    } else {
                        return "ARRI Alexa"
                    }
                }
                
                if trimmedLine.contains("AMIRA") {
                    return "ARRI Amira"
                }
                
                // General ARRI detection
                if trimmedLine.lowercased().contains("arri") {
                    return "ARRI"
                }
                
                // Look for camera model in specific ALE fields
                if trimmedLine.hasPrefix("Camera") || trimmedLine.hasPrefix("Cam") {
                    if let cameraModel = extractARRIModelFromField(trimmedLine) {
                        return "ARRI \(cameraModel)"
                    }
                }
            }
            
            // If we found an ALE file but no specific camera model, assume ARRI
            return "ARRI"
            
        } catch {
            return nil
        }
    }
    
    private func extractARRIModelFromField(_ field: String) -> String? {
        let fieldUpper = field.uppercased()
        
        if fieldUpper.contains("ALEXA MINI LF") { return "Alexa Mini LF" }
        if fieldUpper.contains("ALEXA MINI") { return "Alexa Mini" }
        if fieldUpper.contains("ALEXA LF") { return "Alexa LF" }
        if fieldUpper.contains("ALEXA") { return "Alexa" }
        if fieldUpper.contains("AMIRA") { return "Amira" }
        
        return nil
    }
}