// Core/Services/Camera/XMLMetadataDetectionService.swift
import Foundation

/// Service for detecting cameras via generic XML metadata files
final class XMLMetadataDetectionService {
    static let shared = XMLMetadataDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCameraFromXML(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Common XML metadata files
        let xmlFiles = [
            "metadata.xml",
            "info.xml",
            "camera.xml",
            "settings.xml"
        ]
        
        // Search for XML files in directory structure
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "xml" {
                    if let cameraInfo = parseCameraFromXML(fileURL) {
                        return cameraInfo
                    }
                }
                
                // Also check specific metadata files
                for xmlFile in xmlFiles {
                    if fileURL.lastPathComponent.lowercased() == xmlFile {
                        if let cameraInfo = parseCameraFromXML(fileURL) {
                            return cameraInfo
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - XML Parsing
    
    private func parseCameraFromXML(_ xmlFile: URL) -> String? {
        do {
            let xmlContent = try String(contentsOf: xmlFile, encoding: .utf8)
            
            // Look for common camera metadata tags
            let cameraPatterns = [
                // Generic patterns
                "<camera[^>]*>([^<]+)</camera>",
                "<make[^>]*>([^<]+)</make>",
                "<model[^>]*>([^<]+)</model>",
                "<manufacturer[^>]*>([^<]+)</manufacturer>",
                
                // Attribute patterns
                "camera=\"([^\"]+)\"",
                "make=\"([^\"]+)\"",
                "model=\"([^\"]+)\""
            ]
            
            var make: String?
            var model: String?
            
            for pattern in cameraPatterns {
                if let range = xmlContent.range(of: pattern, options: .regularExpression) {
                    let match = String(xmlContent[range])
                    if let valueRange = match.range(of: ">([^<]+)<", options: .regularExpression) ??
                                       match.range(of: "=\"([^\"]+)\"", options: .regularExpression) {
                        let value = String(match[valueRange])
                            .replacingOccurrences(of: ">", with: "")
                            .replacingOccurrences(of: "<", with: "")
                            .replacingOccurrences(of: "=\"", with: "")
                            .replacingOccurrences(of: "\"", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if pattern.contains("make") || pattern.contains("manufacturer") {
                            make = value
                        } else if pattern.contains("model") {
                            model = value
                        } else if pattern.contains("camera") {
                            return value // Direct camera name
                        }
                    }
                }
            }
            
            // Combine make and model if available
            if let make = make, let model = model {
                return "\(make) \(model)"
            } else if let make = make {
                return make
            } else if let model = model {
                return model
            }
            
        } catch {
            // Failed to read XML file
            return nil
        }
        
        return nil
    }
}