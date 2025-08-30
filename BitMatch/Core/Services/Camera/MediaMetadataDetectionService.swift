// Core/Services/Camera/MediaMetadataDetectionService.swift
import Foundation

/// Service for detecting cameras via generic media file metadata
final class MediaMetadataDetectionService {
    static let shared = MediaMetadataDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCameraFromMedia(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Media file extensions to analyze
        let mediaExtensions = ["JPG", "JPEG", "TIFF", "TIF", "DNG", "HEIC"]
        
        // Search for media files
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var mediaFiles: [URL] = []
            
            for case let fileURL as URL in enumerator {
                if mediaExtensions.contains(fileURL.pathExtension.uppercased()) {
                    mediaFiles.append(fileURL)
                    if mediaFiles.count >= 5 { break } // Analyze a few samples
                }
            }
            
            // Try to extract camera info from media files
            for mediaFile in mediaFiles {
                if let cameraInfo = extractCameraFromMediaFile(mediaFile) {
                    return cameraInfo
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Media File Analysis
    
    private func extractCameraFromMediaFile(_ mediaFile: URL) -> String? {
        #if os(macOS)
        // Use macOS metadata system
        if let metadataItem = NSMetadataItem(url: mediaFile) {
            var make: String?
            var model: String?
            
            // Try to get camera make
            if let cameraMake = metadataItem.value(forAttribute: "kMDItemAcquisitionMake" as String) as? String {
                make = cameraMake
            }
            
            // Try to get camera model  
            if let cameraModel = metadataItem.value(forAttribute: "kMDItemAcquisitionModel" as String) as? String {
                model = cameraModel
            }
            
            // Format result
            if let make = make, let model = model {
                return "\(make) \(model)"
            } else if let make = make {
                return make
            } else if let model = model {
                return model
            }
        }
        
        // Fallback: try mdls command
        return extractCameraWithMdls(mediaFile)
        #else
        // iOS doesn't have NSMetadataItem or mdls, return nil
        return nil
        #endif
    }
    
    #if os(macOS)
    private func extractCameraWithMdls(_ mediaFile: URL) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/mdls"
        task.arguments = [mediaFile.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = output.components(separatedBy: .newlines)
        var make: String?
        var model: String?
        
        for line in lines {
            if line.contains("kMDItemAcquisitionMake") && !line.contains("ColorMake") {
                make = extractQuotedValue(from: line)
            }
            
            if line.contains("kMDItemAcquisitionModel") && !line.contains("ColorModel") {
                model = extractQuotedValue(from: line)
            }
        }
        
        // Format result
        if let make = make, let model = model {
            return "\(make) \(model)"
        } else if let make = make {
            return make
        } else if let model = model {
            return model
        }
        
        return nil
    }
    #endif
    
    private func extractQuotedValue(from line: String) -> String? {
        if let range = line.range(of: "\"([^\"]*)\"", options: .regularExpression) {
            let quotedMatch = String(line[range])
            return quotedMatch.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}