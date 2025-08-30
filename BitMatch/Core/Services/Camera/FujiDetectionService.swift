// Core/Services/Camera/FujiDetectionService.swift
import Foundation

/// Specialized service for detecting Fujifilm cameras via RAF files and metadata
final class FujiDetectionService {
    static let shared = FujiDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectFujiCamera(at url: URL) -> String? {
        return checkFujiRAFFiles(at: url)
    }
    
    // MARK: - RAF File Detection
    
    private func checkFujiRAFFiles(at url: URL) -> String? {
        let fm = FileManager.default
        var rafFiles: [URL] = []
        
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.uppercased() == "RAF" {
                    rafFiles.append(fileURL)
                }
                
                if rafFiles.count >= 3 { break }
            }
        }
        
        guard !rafFiles.isEmpty else { return nil }
        
        for rafFile in rafFiles {
            if let cameraModel = extractCameraModelFromRAF(rafFile) {
                return "Fujifilm \(cameraModel)"
            }
        }
        
        return "Fujifilm"
    }
    
    private func extractCameraModelFromRAF(_ rafFile: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: rafFile) else { return nil }
        defer { try? fileHandle.close() }
        
        let headerSize = 1024
        guard let headerData = try? fileHandle.read(upToCount: headerSize) else { return nil }
        
        guard let headerString = String(data: headerData, encoding: .ascii) else { return nil }
        
        let fujiModels = [
            "X-T30 II": "X-T30 II",
            "X-T30": "X-T30",
            "X-T5": "X-T5",
            "X-T4": "X-T4",
            "X-T3": "X-T3",
            "X-T2": "X-T2",
            "X-T1": "X-T1",
            "X-T20": "X-T20",
            "X-H2S": "X-H2S",
            "X-H2": "X-H2",
            "X-H1": "X-H1",
            "X-Pro3": "X-Pro3",
            "X-Pro2": "X-Pro2",
            "X-Pro1": "X-Pro1",
            "X100VI": "X100VI",
            "X100V": "X100V",
            "X100F": "X100F",
            "X100T": "X100T",
            "X100S": "X100S",
            "X-S20": "X-S20",
            "X-S10": "X-S10",
            "GFX100S": "GFX100S",
            "GFX100": "GFX100",
            "GFX50S": "GFX50S",
            "GFX50R": "GFX50R"
        ]
        
        for (modelKey, modelName) in fujiModels {
            if headerString.contains(modelKey) {
                return modelName
            }
        }
        
        if headerString.contains("FUJIFILM") {
            let lines = headerString.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("X-") || trimmed.hasPrefix("GFX") {
                    return trimmed
                }
            }
        }
        
        return nil
    }
}