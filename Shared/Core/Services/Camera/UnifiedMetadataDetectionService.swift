// Core/Services/Camera/UnifiedMetadataDetectionService.swift
import Foundation

/// Unified service for detecting cameras via video and media file metadata
final class UnifiedMetadataDetectionService: Sendable {
    static let shared = UnifiedMetadataDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    /// Detect camera from any metadata source (video or media files)
    func detectCameraFromMetadata(at url: URL) -> String? {
        // Try video metadata first (usually more reliable)
        if let videoResult = detectCameraFromVideo(at: url) {
            return videoResult
        }

        // A cancelled detection must not start another full scan.
        guard !Task.isCancelled else { return nil }

        // Fall back to media file metadata
        if let mediaResult = detectCameraFromMedia(at: url) {
            return mediaResult
        }

        return nil
    }
    
    // MARK: - Video Metadata Detection
    
    private func detectCameraFromVideo(at url: URL) -> String? {
        guard let videoFile = findVideoFile(at: url) else { return nil }
        
        #if os(macOS)
        // Try macOS metadata first (fastest and most reliable)
        if let result = extractVideoMetadataWithMdls(videoFile) {
            return result
        }

        // A cancellation during mdls must not launch another subprocess.
        guard !Task.isCancelled else { return nil }

        // Try ffprobe if available (more detailed)
        if let result = extractVideoMetadataWithFFProbe(videoFile) {
            return result
        }
        #endif
        
        return nil
    }
    
    // MARK: - Media File Metadata Detection
    
    private func detectCameraFromMedia(at url: URL) -> String? {
        let fm = FileManager.default
        
        // Media file extensions to analyze
        let mediaExtensions = ["JPG", "JPEG", "TIFF", "TIF", "DNG", "HEIC"]
        
        // Search for media files
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var mediaFiles: [URL] = []
            
            for case let fileURL as URL in enumerator {
                guard !Task.isCancelled else { return nil }
                if mediaExtensions.contains(fileURL.pathExtension.uppercased()) {
                    mediaFiles.append(fileURL)
                    if mediaFiles.count >= 5 { break } // Analyze a few samples
                }
            }
            
            // Try to extract camera info from media files. Spotlight/mdls is
            // macOS-only; iOS media metadata comes from the other services.
            // A cancelled detection must not start another subprocess.
            for mediaFile in mediaFiles {
                #if os(macOS)
                guard !Task.isCancelled else { return nil }
                if let cameraInfo = extractCameraFromMediaFile(mediaFile) {
                    return cameraInfo
                }
                #endif
            }
        }
        
        return nil
    }
    
    // MARK: - File Discovery
    
    private func findVideoFile(at url: URL) -> URL? {
        let fm = FileManager.default
        let videoExtensions = ["MP4", "MOV", "M4V", "AVI", "MKV", "HEVC"]
        
        // Search recursively for video files
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if Task.isCancelled { return nil }
                if videoExtensions.contains(fileURL.pathExtension.uppercased()) {
                    return fileURL
                }
            }
        }
        
        return nil
    }
    
    // MARK: - macOS-specific Metadata Extraction
    
    #if os(macOS)
    /// Wait for a metadata subprocess, terminating it early when the
    /// current task is cancelled. Returns false when cancelled or when the
    /// process could not launch; the caller's exit-status handling is
    /// unchanged. Outside a task context this behaves like waitUntilExit().
    private func waitForExitUnlessCancelled(_ task: Process) -> Bool {
        // Never spawn the subprocess when already cancelled.
        guard !Task.isCancelled else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }
        do {
            try task.run()
        } catch {
            return false
        }
        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled {
                task.terminate()
                // Bounded wait after requesting termination: a wedged
                // process must not block cancellation indefinitely. This
                // bounds the caller's wait, not the process's exit.
                _ = semaphore.wait(timeout: .now() + .seconds(2))
                return false
            }
        }
        return true
    }

    private func extractVideoMetadataWithMdls(_ videoFile: URL) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/mdls"
        task.arguments = ["-name", "kMDItemAcquisitionMake", "-name", "kMDItemAcquisitionModel", videoFile.path]

        let pipe = Pipe()
        task.standardOutput = pipe

        guard waitForExitUnlessCancelled(task) else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return parseMdlsOutput(output)
    }

    private func extractVideoMetadataWithFFProbe(_ videoFile: URL) -> String? {
        let task = Process()
        task.launchPath = "/usr/local/bin/ffprobe"
        task.arguments = [
            "-v", "quiet",
            "-select_streams", "v:0",
            "-show_entries", "format_tags=make,model",
            "-of", "csv=p=0",
            videoFile.path
        ]

        let pipe = Pipe()
        task.standardOutput = pipe

        guard waitForExitUnlessCancelled(task),
              task.terminationStatus == 0 else {
            // FFProbe not available or detection cancelled, continue
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return parseFFProbeOutput(output)
    }
    
    private func extractCameraFromMediaFile(_ mediaFile: URL) -> String? {
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
            
            return formatCameraInfo(make: make, model: model)
        }
        
        return nil
    }
    #endif
    
    // MARK: - Output Parsing
    
    private func parseMdlsOutput(_ output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        var make: String?
        var model: String?
        
        for line in lines {
            if line.contains("kMDItemAcquisitionMake") {
                let components = line.components(separatedBy: "= ")
                if components.count > 1 {
                    make = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            if line.contains("kMDItemAcquisitionModel") {
                let components = line.components(separatedBy: "= ")
                if components.count > 1 {
                    model = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        
        return formatCameraInfo(make: make, model: model)
    }
    
    private func parseFFProbeOutput(_ output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let components = line.components(separatedBy: ",")
            if components.count >= 2 {
                let make = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let model = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return formatCameraInfo(make: make.isEmpty ? nil : make, model: model.isEmpty ? nil : model)
            }
        }
        return nil
    }
    
    private func formatCameraInfo(make: String?, model: String?) -> String? {
        // mdls prints "(null)" for a missing attribute; that is no answer,
        // not a camera named "(null)" (audit finding C).
        func present(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty, trimmed != "(null)" else { return nil }
            return trimmed
        }
        switch (present(make), present(model)) {
        case (let m?, let mod?):
            return "\(m) \(mod)"
        case (let m?, nil):
            return m
        case (nil, let mod?):
            return mod
        case (nil, nil):
            return nil
        }
    }
}