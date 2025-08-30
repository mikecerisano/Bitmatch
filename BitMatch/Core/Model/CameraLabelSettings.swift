import Foundation

// MARK: - Camera Label Settings Model
struct CameraLabelSettings: Codable {
    var label: String = ""
    var position: LabelPosition = .prefix  // Changed default to prefix
    var separator: Separator = .underscore
    var autoNumber: Bool = true
    var groupByCamera: Bool = false  // NEW: Automatically group files by detected camera type
    
    enum LabelPosition: String, CaseIterable, Codable {
        case prefix = "Prefix"
        case suffix = "Suffix"
    }
    
    enum Separator: String, CaseIterable, Codable {
        case space = " "
        case dash = "-"
        case underscore = "_"
        
        var displayName: String {
            switch self {
            case .space: return "Space"
            case .dash: return "Dash (-)"
            case .underscore: return "Underscore (_)"
            }
        }
    }
    
    // Format the folder name with label
    func formatFolderName(_ base: String) -> String {
        guard !label.isEmpty else { return base }
        let cleanLabel = label.replacingOccurrences(of: " ", with: "_")
        
        switch position {
        case .prefix:
            return "\(cleanLabel)\(separator.rawValue)\(base)"
        case .suffix:
            return "\(base)\(separator.rawValue)\(cleanLabel)"
        }
    }
    
    // Generate unique name if destination exists
    func generateUniqueName(base: String, at url: URL) -> String {
        let fm = FileManager.default
        var name = formatFolderName(base)
        var counter = 2
        
        while fm.fileExists(atPath: url.appendingPathComponent(name).path) {
            if autoNumber {
                name = formatFolderName(base) + " (\(counter))"
                counter += 1
            } else {
                break
            }
        }
        return name
    }
    
    // Generate camera-specific parent folder path if grouping is enabled
    func generateCameraGroupPath(for sourceURL: URL, in destinationURL: URL) -> (cameraFolder: URL, dumpFolder: URL) {
        guard groupByCamera else { 
            // No grouping - dump goes directly to destination
            let dumpFolder = destinationURL.appendingPathComponent(generateUniqueName(base: sourceURL.lastPathComponent, at: destinationURL), isDirectory: true)
            return (cameraFolder: destinationURL, dumpFolder: dumpFolder)
        }
        
        // Try to detect camera designation from the source folder
        if let cameraSuggestion = CameraNamingService.getBestCameraSuggestion(for: sourceURL) {
            // Create camera subfolder path (e.g., /Backup/A_CAM/)
            let cameraSubfolderName = cameraSuggestion.cameraDesignation.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
            let cameraFolder = destinationURL.appendingPathComponent(cameraSubfolderName, isDirectory: true)
            
            // Create dump folder inside camera folder (e.g., /Backup/A_CAM/LOST_BOYS_A_CAM_FX6/)
            let dumpFolder = cameraFolder.appendingPathComponent(generateUniqueName(base: sourceURL.lastPathComponent, at: cameraFolder), isDirectory: true)
            
            return (cameraFolder: cameraFolder, dumpFolder: dumpFolder)
        }
        
        // If no camera detected, don't group - dump goes directly to destination
        let dumpFolder = destinationURL.appendingPathComponent(generateUniqueName(base: sourceURL.lastPathComponent, at: destinationURL), isDirectory: true)
        return (cameraFolder: destinationURL, dumpFolder: dumpFolder)
    }
}
