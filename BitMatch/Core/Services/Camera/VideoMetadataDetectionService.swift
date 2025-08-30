// Core/Services/Camera/VideoMetadataDetectionService.swift
import Foundation

/// Universal video metadata detection service for all camera brands
final class VideoMetadataDetectionService {
    static let shared = VideoMetadataDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectCameraFromVideo(at url: URL) -> String? {
        guard let videoFile = findVideoFile(at: url) else { return nil }
        
        #if os(macOS)
        // Try macOS metadata first (fastest and most reliable)
        if let result = extractVideoMetadataWithMdls(videoFile) {
            return result
        }
        
        // Try ffprobe if available (more detailed)
        if let result = extractVideoMetadataWithFFProbe(videoFile) {
            return result
        }
        #endif
        
        return nil
    }
    
    // MARK: - Private Implementation
    
    private func findVideoFile(at url: URL) -> URL? {
        let fm = FileManager.default
        let videoExtensions = ["MP4", "MOV", "M4V", "AVI", "MKV", "HEVC"]
        
        // Search recursively for video files
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if videoExtensions.contains(fileURL.pathExtension.uppercased()) {
                    return fileURL
                }
            }
        }
        
        return nil
    }
    
    #if os(macOS)
    private func extractVideoMetadataWithMdls(_ videoFile: URL) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/mdls"
        task.arguments = [videoFile.path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = output.components(separatedBy: .newlines)
        var make: String?
        var model: String?
        
        // Extract make and model from metadata
        for line in lines {
            if (line.contains("kMDItemAcquisitionMake") || line.contains("Make")) && !line.contains("ColorMake") {
                make = extractQuotedValue(from: line)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if (line.contains("kMDItemAcquisitionModel") || line.contains("Model")) && !line.contains("ColorModel") {
                model = extractQuotedValue(from: line)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Sometimes camera info is in comment or description fields
            if line.contains("kMDItemComment") || line.contains("kMDItemDescription") {
                if let comment = extractQuotedValue(from: line) {
                    if let cameraFromComment = parseCameraFromComment(comment) {
                        return cameraFromComment
                    }
                }
            }
        }
        
        // Format the camera information
        return formatCameraName(make: make, model: model)
    }
    #endif
    
    #if os(macOS)
    private func extractVideoMetadataWithFFProbe(_ videoFile: URL) -> String? {
        // Check if ffprobe is available (common locations)
        let possiblePaths = ["/usr/local/bin/ffprobe", "/opt/homebrew/bin/ffprobe", "/usr/bin/ffprobe"]
        var ffprobePath: String?
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                ffprobePath = path
                break
            }
        }
        
        guard let validPath = ffprobePath else { return nil }
        
        let task = Process()
        task.launchPath = validPath
        task.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            videoFile.path
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        // Look for camera metadata in JSON output
        return parseCameraFromFFProbeJSON(output)
    }
    #endif
    
    private func parseCameraFromComment(_ comment: String) -> String? {
        let commentUpper = comment.uppercased()
        
        // Check for various camera brands in comments
        let brands = [
            ("CANON", "Canon"),
            ("SONY", "Sony"),
            ("PANASONIC", "Panasonic"),
            ("NIKON", "Nikon"),
            ("FUJIFILM", "Fujifilm"),
            ("FUJI", "Fujifilm"),
            ("OLYMPUS", "Olympus"),
            ("LEICA", "Leica"),
            ("BLACKMAGIC", "Blackmagic"),
            ("RED", "RED"),
            ("ARRI", "ARRI"),
            ("DJI", "DJI"),
            ("GOPRO", "GoPro")
        ]
        
        for (brandPattern, brandName) in brands {
            if commentUpper.contains(brandPattern) {
                return brandName
            }
        }
        
        return nil
    }
    
    private func formatCameraName(make: String?, model: String?) -> String? {
        guard let make = make, !make.isEmpty else { return nil }
        
        // Clean and standardize make
        let cleanMake = cleanCameraMake(make)
        
        if let model = model, !model.isEmpty {
            let cleanModel = cleanCameraModel(model, make: cleanMake)
            return "\(cleanMake) \(cleanModel)"
        }
        
        return cleanMake
    }
    
    private func cleanCameraMake(_ make: String) -> String {
        let makeUpper = make.uppercased()
        
        // Standardize common camera makes
        if makeUpper.contains("CANON") { return "Canon" }
        if makeUpper.contains("SONY") { return "Sony" }
        if makeUpper.contains("PANASONIC") { return "Panasonic" }
        if makeUpper.contains("NIKON") { return "Nikon" }
        if makeUpper.contains("FUJIFILM") || makeUpper.contains("FUJI") { return "Fujifilm" }
        if makeUpper.contains("OLYMPUS") { return "Olympus" }
        if makeUpper.contains("LEICA") { return "Leica" }
        if makeUpper.contains("BLACKMAGIC") { return "Blackmagic" }
        if makeUpper.contains("RED") { return "RED" }
        if makeUpper.contains("ARRI") { return "ARRI" }
        if makeUpper.contains("DJI") { return "DJI" }
        if makeUpper.contains("GOPRO") { return "GoPro" }
        if makeUpper.contains("APPLE") { return "iPhone" }
        
        return make.capitalized
    }
    
    private func cleanCameraModel(_ model: String, make: String) -> String {
        // Remove make from model if it's redundant
        var cleanModel = model
        let makeUpper = make.uppercased()
        let modelUpper = model.uppercased()
        
        // Remove redundant make from model name
        if modelUpper.hasPrefix(makeUpper) {
            cleanModel = String(cleanModel.dropFirst(make.count)).trimmingCharacters(in: .whitespaces)
        }
        
        return cleanModel
    }
    
    private func parseCameraFromFFProbeJSON(_ jsonOutput: String) -> String? {
        // Simple JSON parsing for camera metadata
        // Look for common metadata fields that contain camera info
        let patterns = [
            "\"make\"\\s*:\\s*\"([^\"]+)\"",
            "\"model\"\\s*:\\s*\"([^\"]+)\"",
            "\"camera_make\"\\s*:\\s*\"([^\"]+)\"",
            "\"camera_model\"\\s*:\\s*\"([^\"]+)\"",
            "\"manufacturer\"\\s*:\\s*\"([^\"]+)\""
        ]
        
        var make: String?
        var model: String?
        
        for pattern in patterns {
            if let range = jsonOutput.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let match = String(jsonOutput[range])
                if let valueRange = match.range(of: "\"([^\"]+)\"", options: .regularExpression) {
                    let value = String(match[valueRange]).replacingOccurrences(of: "\"", with: "")
                    
                    if pattern.contains("make") || pattern.contains("manufacturer") {
                        make = value
                    } else if pattern.contains("model") {
                        model = value
                    }
                }
            }
        }
        
        return formatCameraName(make: make, model: model)
    }
    
    private func extractQuotedValue(from line: String) -> String? {
        // Extract value between quotes like: kMDItemAcquisitionModel = "X-T30 II"
        if let range = line.range(of: "\"([^\"]*)\"", options: .regularExpression) {
            let quotedMatch = String(line[range])
            return quotedMatch.replacingOccurrences(of: "\"", with: "")
        }
        return nil
    }
}