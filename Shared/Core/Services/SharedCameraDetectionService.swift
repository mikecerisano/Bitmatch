// SharedCameraDetectionService.swift - Platform-agnostic camera detection
import Foundation
import AVFoundation

@MainActor
class SharedCameraDetectionService: CameraDetectionService {
    
    func detectCamera(from folderURL: URL) async -> CameraDetectionResult {
        let startTime = Date()
        var metadata: [String: Any] = [:]
        var confidence: Double = 0.0
        var detectedCard: CameraCard? = nil
        var detectionMethod = "unknown"
        
        do {
            // Step 1: Analyze folder structure
            let folderStructure = try await analyzeFolderStructure(at: folderURL)
            metadata.merge(folderStructure) { _, new in new }
            
            // Step 2: Check for camera-specific folder patterns
            let folderName = folderURL.lastPathComponent.uppercased()
            let (manufacturer, model, folderConfidence) = detectFromFolderName(folderName)
            
            if folderConfidence > confidence {
                confidence = folderConfidence
                detectionMethod = "folder_structure"
            }
            
            // Step 3: Analyze file extensions and naming patterns
            let fileURLs = try await getFileList(from: folderURL)
            let (fileManufacturer, fileModel, fileConfidence) = await detectFromFilePatterns(fileURLs)
            
            if fileConfidence > confidence {
                confidence = fileConfidence
                detectionMethod = "file_patterns"
            }
            
            // Step 4: Extract metadata from video files
            if confidence < 0.8 {
                let videoURLs = fileURLs.filter { isVideoFile($0) }
                if let videoURL = videoURLs.first {
                    do {
                        let videoMetadata = try await extractVideoMetadata(from: videoURL)
                        metadata.merge(videoMetadata) { _, new in new }
                        
                        let (videoManufacturer, videoModel, videoConfidence) = extractCameraFromVideoMetadata(videoMetadata)
                        if videoConfidence > confidence {
                            confidence = videoConfidence
                            detectionMethod = "video_metadata"
                        }
                    } catch {
                        // Video metadata extraction failed, continue with other methods
                    }
                }
            }
            
            // Step 5: Look for XML sidecar files
            if confidence < 0.8 {
                let xmlURLs = fileURLs.filter { $0.pathExtension.lowercased() == "xml" }
                for xmlURL in xmlURLs.prefix(3) { // Only check first 3 XML files
                    do {
                        let xmlMetadata = try await parseXMLMetadata(from: xmlURL)
                        let (xmlManufacturer, xmlModel, xmlConfidence) = extractCameraFromXMLMetadata(xmlMetadata)
                        if xmlConfidence > confidence {
                            confidence = xmlConfidence
                            detectionMethod = "xml_metadata"
                            metadata.merge(xmlMetadata) { _, new in new }
                        }
                    } catch {
                        // XML parsing failed, continue
                    }
                }
            }
            
            // Create camera card if we have sufficient confidence
            if confidence > 0.5 {
                let finalManufacturer = manufacturer ?? fileManufacturer ?? "Unknown"
                let finalModel = model ?? fileModel
                
                detectedCard = CameraCard(
                    name: finalModel ?? finalManufacturer,
                    manufacturer: finalManufacturer,
                    model: finalModel,
                    fileCount: fileURLs.count,
                    totalSize: calculateTotalSize(fileURLs),
                    detectionConfidence: confidence,
                    metadata: metadata
                )
            }
            
        } catch {
            metadata["error"] = error.localizedDescription
            confidence = 0.0
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return CameraDetectionResult(
            cameraCard: detectedCard,
            confidence: confidence,
            metadata: metadata,
            detectionMethod: detectionMethod,
            processingTime: processingTime
        )
    }
    
    func analyzeFolderStructure(at url: URL) async throws -> [String: Any] {
        var structure: [String: Any] = [:]
        
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        var fileCount = 0
        var folderCount = 0
        var extensions: Set<String> = []
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if isDirectory {
                folderCount += 1
            } else {
                fileCount += 1
                extensions.insert(fileURL.pathExtension.lowercased())
            }
        }
        
        structure["total_files"] = fileCount
        structure["total_folders"] = folderCount
        structure["file_extensions"] = Array(extensions).sorted()
        structure["folder_name"] = url.lastPathComponent
        
        return structure
    }
    
    func extractVideoMetadata(from fileURL: URL) async throws -> [String: Any] {
        let asset = AVAsset(url: fileURL)
        var metadata: [String: Any] = [:]
        
        // Get common metadata
        for item in await asset.metadata {
            if let key = item.commonKey?.rawValue, let value = try? await item.load(.value) {
                metadata[key] = value
            }
        }
        
        // Get format-specific metadata
        for format in await asset.availableMetadataFormats {
            let items = await asset.metadata(forFormat: format)
            for item in items {
                if let key = item.key as? String, let value = try? await item.load(.value) {
                    metadata["format_\(format.rawValue)_\(key)"] = value
                }
            }
        }
        
        return metadata
    }
    
    func parseXMLMetadata(from fileURL: URL) async throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        var metadata: [String: Any] = [:]
        
        // Simple XML parsing for common camera metadata patterns
        if let xmlString = String(data: data, encoding: .utf8) {
            metadata["xml_content_length"] = xmlString.count
            
            // Look for common camera metadata patterns
            let patterns = [
                "camera": #"<camera[^>]*>([^<]+)</camera>"#,
                "manufacturer": #"<manufacturer[^>]*>([^<]+)</manufacturer>"#,
                "model": #"<model[^>]*>([^<]+)</model>"#,
                "device": #"<device[^>]*>([^<]+)</device>"#,
            ]
            
            for (key, pattern) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(xmlString.startIndex..., in: xmlString)
                    if let match = regex.firstMatch(in: xmlString, range: range),
                       let valueRange = Range(match.range(at: 1), in: xmlString) {
                        metadata[key] = String(xmlString[valueRange])
                    }
                }
            }
        }
        
        return metadata
    }
    
    // MARK: - Private Helper Methods
    
    private func getFileList(from folderURL: URL) async throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey])
        var fileURLs: [URL] = []
        
        while let url = enumerator?.nextObject() as? URL {
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                fileURLs.append(url)
            }
        }
        
        return fileURLs
    }
    
    private func detectFromFolderName(_ folderName: String) -> (manufacturer: String?, model: String?, confidence: Double) {
        let patterns: [(String, String?, Double)] = [
            ("ARRI", "ALEXA", 0.9),
            ("CANON", nil, 0.8),
            ("SONY", nil, 0.8),
            ("PANASONIC", nil, 0.8),
            ("FUJI", nil, 0.8),
            ("BLACKMAGIC", nil, 0.8),
            ("RED", nil, 0.9),
        ]
        
        for (manufacturer, model, confidence) in patterns {
            if folderName.contains(manufacturer) {
                return (manufacturer, model, confidence)
            }
        }
        
        return (nil, nil, 0.0)
    }
    
    private func detectFromFilePatterns(_ fileURLs: [URL]) async -> (manufacturer: String?, model: String?, confidence: Double) {
        let fileExtensions = Set(fileURLs.map { $0.pathExtension.lowercased() })
        
        // Camera-specific file extension patterns
        if fileExtensions.contains("ari") { return ("ARRI", "ALEXA", 0.95) }
        if fileExtensions.contains("r3d") { return ("RED", nil, 0.95) }
        if fileExtensions.contains("braw") { return ("Blackmagic Design", nil, 0.95) }
        if fileExtensions.intersection(["mxf", "mov"]).count > 0 {
            return ("Professional Camera", nil, 0.6)
        }
        
        return (nil, nil, 0.0)
    }
    
    private func extractCameraFromVideoMetadata(_ metadata: [String: Any]) -> (manufacturer: String?, model: String?, confidence: Double) {
        // Look for camera information in video metadata
        for (key, value) in metadata {
            let keyLower = key.lowercased()
            let valueString = "\(value)".lowercased()
            
            if keyLower.contains("camera") || keyLower.contains("device") {
                if valueString.contains("arri") { return ("ARRI", nil, 0.9) }
                if valueString.contains("canon") { return ("Canon", nil, 0.9) }
                if valueString.contains("sony") { return ("Sony", nil, 0.9) }
                if valueString.contains("panasonic") { return ("Panasonic", nil, 0.9) }
            }
        }
        
        return (nil, nil, 0.0)
    }
    
    private func extractCameraFromXMLMetadata(_ metadata: [String: Any]) -> (manufacturer: String?, model: String?, confidence: Double) {
        if let manufacturer = metadata["manufacturer"] as? String {
            let model = metadata["model"] as? String
            return (manufacturer, model, 0.85)
        }
        
        if let camera = metadata["camera"] as? String {
            return (camera, nil, 0.8)
        }
        
        return (nil, nil, 0.0)
    }
    
    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mov", "mp4", "avi", "mxf", "r3d", "ari", "braw", "dnxhd", "prores"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
    
    private func calculateTotalSize(_ fileURLs: [URL]) -> Int64 {
        return fileURLs.compactMap { url in
            try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        }.reduce(0, +)
    }
}