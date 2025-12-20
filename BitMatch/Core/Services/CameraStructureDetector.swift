// Core/Services/CameraStructureDetector.swift - Camera file structure detection
import Foundation

// MARK: - Camera Structure Detector

struct CameraStructureDetector {
    
    /// Detect camera type and structure at given volume
    static func detectCameraType(at volume: URL) async -> CameraCard? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = performDetection(at: volume)
                continuation.resume(returning: result)
            }
        }
    }
    
    private static func performDetection(at volume: URL) -> CameraCard? {
        // Skip system volumes and hidden volumes
        guard isValidVolumeForDetection(volume) else {
            return nil
        }
        
        // Try each camera type detection pattern
        for detector in cameraDetectors {
            if let detection = detector.detect(at: volume) {
                // Future enhancement: populate volume info if needed for UI
                // guard let volumeInfo = VolumeScanner.getVolumeInfo(for: volume) else {
                //     continue
                // }
                
                return CameraCard(
                    name: detection.cameraType.rawValue,
                    manufacturer: detection.cameraType.rawValue,
                    model: nil,
                    fileCount: 0, // Placeholder; detailed analysis step populates counts
                    totalSize: 0, // Placeholder; detailed analysis step populates size
                    detectionConfidence: {
                        switch detection.confidence {
                        case .high: return 0.9
                        case .medium: return 0.7
                        case .low: return 0.5
                        }
                    }(),
                    metadata: [:],
                    volumeURL: volume,
                    cameraType: detection.cameraType,
                    mediaPath: detection.mediaPath
                )
            }
        }
        
        return nil
    }
    
    private static func isValidVolumeForDetection(_ volume: URL) -> Bool {
        // Skip system volumes
        let systemPaths = ["/System", "/", "/Applications", "/Library", "/usr"]
        if systemPaths.contains(volume.path) {
            return false
        }
        
        // Check if it's a removable volume or contains camera-like structures
        do {
            let resourceValues = try volume.resourceValues(forKeys: [
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsLocalKey
            ])
            
            // Prefer removable/ejectable volumes (SD cards, external drives)
            if resourceValues.volumeIsRemovable == true || 
               resourceValues.volumeIsEjectable == true {
                return true
            }
            
            // But also check internal volumes that might have camera structures
            // (for testing with copied camera folders)
            return resourceValues.volumeIsLocal == true
            
        } catch {
            return false
        }
    }
}

// MARK: - Detection Result

struct CameraStructureResult {
    let cameraType: CameraType
    let mediaPath: URL
    let confidence: DetectionConfidence
}

enum DetectionConfidence {
    case high      // Multiple indicators match
    case medium    // Some indicators match
    case low       // Weak indicators
}

// MARK: - Camera Type Definitions

// MARK: - Camera Detectors

protocol CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult?
}

private let cameraDetectors: [CameraDetector] = [
    REDCameraDetector(),
    ARRICameraDetector(),
    BlackmagicDetector(),
    SonyCameraDetector(),
    CanonCameraDetector(),
    PanasonicDetector(),
    FujifilmDetector(),
    NikonDetector(),
    GoProDetector(),
    DJIDetector(),
    Insta360Detector(),
    GenericDCIMDetector(),
    GenericMediaDetector()
]

// MARK: - Specific Camera Detectors

struct REDCameraDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["RED", "REDMAG", "R3D"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                // Look for .R3D files or RED-specific structure
                if containsREDMedia(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .redCamera,
                        mediaPath: folderURL,
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsREDMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["r3d", "R3D"])
    }
}

struct ARRICameraDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["ARRIRAW", "ARRI", "CLIPS"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsARRIMedia(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .arri,
                        mediaPath: folderURL,
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsARRIMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["ari", "ARI", "mxf", "MXF"])
    }
}

struct BlackmagicDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["BRAW", "Blackmagic RAW"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsBlackmagicMedia(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .blackmagic,
                        mediaPath: folderURL,
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsBlackmagicMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["braw", "BRAW"])
    }
}

struct SonyCameraDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        // Check for Sony-specific folders and files
        let sonyFolders = ["PRIVATE", "XDCAM", "DCIM"]
        
        for folder in sonyFolders {
            let folderURL = volume.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsSonyMedia(at: folderURL) || containsSonyStructure(at: volume) {
                    return CameraStructureResult(
                        cameraType: .sony,
                        mediaPath: findBestMediaPath(at: volume, candidates: sonyFolders),
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsSonyMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["mts", "MTS", "mp4", "MP4", "xavc", "XAVC"])
    }
    
    private func containsSonyStructure(at volume: URL) -> Bool {
        // Look for Sony-specific files
        let sonyFiles = ["DISCMETA.XML", "MEDPRO.XML"]
        return sonyFiles.contains { file in
            FileManager.default.fileExists(atPath: volume.appendingPathComponent(file).path)
        }
    }
}

struct CanonCameraDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsCanonMedia(at: dcimURL) {
            return CameraStructureResult(
                cameraType: .canon,
                mediaPath: dcimURL,
                confidence: .high
            )
        }
        
        return nil
    }
    
    private func containsCanonMedia(at path: URL) -> Bool {
        // Look for Canon-specific file patterns
        return containsFilesWithExtensions(at: path, extensions: ["cr2", "CR2", "cr3", "CR3", "mov", "MOV"]) ||
               containsCanonFolders(at: path)
    }
    
    private func containsCanonFolders(at path: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            // Canon cameras often create folders like "100CANON", "101CANON", etc.
            return contents.contains { $0.contains("CANON") || $0.matchesRegex("\\d{3}[A-Z]+") }
        } catch {
            return false
        }
    }
}

struct PanasonicDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["DCIM", "PRIVATE", "P2"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsPanasonicMedia(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .panasonic,
                        mediaPath: folderURL,
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsPanasonicMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["mts", "MTS", "mp4", "MP4", "rw2", "RW2"])
    }
}

struct FujifilmDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsFujifilmMedia(at: dcimURL) {
            return CameraStructureResult(
                cameraType: .fujifilm,
                mediaPath: dcimURL,
                confidence: .high
            )
        }
        
        return nil
    }
    
    private func containsFujifilmMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["raf", "RAF", "jpg", "JPG"]) ||
               containsFujifilmFolders(at: path)
    }
    
    private func containsFujifilmFolders(at path: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            return contents.contains { $0.contains("FUJI") }
        } catch {
            return false
        }
    }
}

struct NikonDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsNikonMedia(at: dcimURL) {
            return CameraStructureResult(
                cameraType: .nikon,
                mediaPath: dcimURL,
                confidence: .high
            )
        }
        
        return nil
    }
    
    private func containsNikonMedia(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["nef", "NEF", "nrw", "NRW", "jpg", "JPG"]) ||
               containsNikonFolders(at: path)
    }
    
    private func containsNikonFolders(at path: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            return contents.contains { $0.contains("NIKON") }
        } catch {
            return false
        }
    }
}

struct GoProDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsGoProMedia(at: dcimURL) {
            return CameraStructureResult(
                cameraType: .gopro,
                mediaPath: dcimURL,
                confidence: .high
            )
        }
        
        return nil
    }
    
    private func containsGoProMedia(at path: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            // GoPro cameras create folders like "100GOPRO", "101GOPRO"
            return contents.contains { $0.contains("GOPRO") }
        } catch {
            return false
        }
    }
}

struct DJIDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["DCIM", "DJI"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsDJIMedia(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .dji,
                        mediaPath: folderURL,
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsDJIMedia(at path: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
            // DJI drones often have "DJI_" prefixed files or folders
            return contents.contains { $0.contains("DJI") }
        } catch {
            return containsFilesWithExtensions(at: path, extensions: ["mp4", "MP4", "jpg", "JPG"])
        }
    }
}

struct Insta360Detector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["DCIM", "INSTA360"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsInsta360Media(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .insta360,
                        mediaPath: folderURL,
                        confidence: .high
                    )
                }
            }
        }
        
        return nil
    }
    
    private func containsInsta360Media(at path: URL) -> Bool {
        return containsFilesWithExtensions(at: path, extensions: ["insv", "INSV", "insp", "INSP"])
    }
}

struct GenericDCIMDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsMediaFiles(at: dcimURL) {
            return CameraStructureResult(
                cameraType: .genericDCIM,
                mediaPath: dcimURL,
                confidence: .medium
            )
        }
        
        return nil
    }
}

struct GenericMediaDetector: CameraDetector {
    func detect(at volume: URL) -> CameraStructureResult? {
        let patterns = ["MEDIA", "VIDEO", "PHOTO", "Pictures", "Movies"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsMediaFiles(at: folderURL) {
                    return CameraStructureResult(
                        cameraType: .genericMedia,
                        mediaPath: folderURL,
                        confidence: .low
                    )
                }
            }
        }
        
        return nil
    }
}

// MARK: - Helper Functions

private func containsFilesWithExtensions(at path: URL, extensions: [String]) -> Bool {
    // Bounded, shallow scan to prevent traversing entire large volumes
    let lowercaseExtensions = extensions.map { $0.lowercased() }
    let maxDepth = 3
    let maxScanned = 50_000
    var scanned = 0

    func scan(_ url: URL, depth: Int) -> Bool {
        if depth > maxDepth || scanned >= maxScanned { return false }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        for item in contents {
            var foundHere = false
            autoreleasepool {
                if scanned >= maxScanned { return }
                scanned += 1
                let itemURL = url.appendingPathComponent(item)
                let ext = itemURL.pathExtension.lowercased()
                if lowercaseExtensions.contains(ext) { foundHere = true; return }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue {
                    if scan(itemURL, depth: depth + 1) { foundHere = true; return }
                }
            }
            if foundHere { return true }
        }
        return false
    }

    let found = scan(path, depth: 0)
    if scanned >= maxScanned {
        SharedLogger.debug("CameraStructureDetector: scan reached cap (\(maxScanned)) at \(path.path)", category: .transfer)
    }
    return found
}

private func containsMediaFiles(at path: URL) -> Bool {
    let commonMediaExtensions = [
        "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "heic", "heif",
        "mp4", "mov", "avi", "mkv", "m4v", "mts", "mxf",
        "cr2", "cr3", "nef", "arf", "arw", "dng", "raf", "rw2"
    ]
    
    return containsFilesWithExtensions(at: path, extensions: commonMediaExtensions)
}

private func findBestMediaPath(at volume: URL, candidates: [String]) -> URL {
    // Return the first existing candidate, or fall back to volume root
    for candidate in candidates {
        let candidateURL = volume.appendingPathComponent(candidate)
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
    
    return volume
}

// MARK: - String Extension for Regex

private extension String {
    func matchesRegex(_ pattern: String) -> Bool {
        let range = NSRange(location: 0, length: self.utf16.count)
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.firstMatch(in: self, options: [], range: range) != nil
        } catch {
            // Invalid pattern; treat as non-match
            return false
        }
    }
}
