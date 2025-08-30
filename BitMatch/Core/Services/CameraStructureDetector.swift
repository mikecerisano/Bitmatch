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
                guard let volumeInfo = VolumeScanner.getVolumeInfo(for: volume) else {
                    continue
                }
                
                return CameraCard(
                    volumeURL: volume,
                    cameraType: detection.cameraType,
                    mediaPath: detection.mediaPath,
                    detectedAt: Date(),
                    volumeInfo: volumeInfo
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

struct CameraDetectionResult {
    let cameraType: DetectedCameraType
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
    func detect(at volume: URL) -> CameraDetectionResult?
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["RED", "REDMAG", "R3D"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                // Look for .R3D files or RED-specific structure
                if containsREDMedia(at: folderURL) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["ARRIRAW", "ARRI", "CLIPS"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsARRIMedia(at: folderURL) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["BRAW", "Blackmagic RAW"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsBlackmagicMedia(at: folderURL) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        // Check for Sony-specific folders and files
        let sonyFolders = ["PRIVATE", "XDCAM", "DCIM"]
        
        for folder in sonyFolders {
            let folderURL = volume.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsSonyMedia(at: folderURL) || containsSonyStructure(at: volume) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsCanonMedia(at: dcimURL) {
            return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["DCIM", "PRIVATE", "P2"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsPanasonicMedia(at: folderURL) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsFujifilmMedia(at: dcimURL) {
            return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsNikonMedia(at: dcimURL) {
            return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsGoProMedia(at: dcimURL) {
            return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["DCIM", "DJI"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsDJIMedia(at: folderURL) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["DCIM", "INSTA360"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsInsta360Media(at: folderURL) {
                    return CameraDetectionResult(
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
    func detect(at volume: URL) -> CameraDetectionResult? {
        let dcimURL = volume.appendingPathComponent("DCIM")
        
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            return nil
        }
        
        if containsMediaFiles(at: dcimURL) {
            return CameraDetectionResult(
                cameraType: .genericDCIM,
                mediaPath: dcimURL,
                confidence: .medium
            )
        }
        
        return nil
    }
}

struct GenericMediaDetector: CameraDetector {
    func detect(at volume: URL) -> CameraDetectionResult? {
        let patterns = ["MEDIA", "VIDEO", "PHOTO", "Pictures", "Movies"]
        
        for pattern in patterns {
            let folderURL = volume.appendingPathComponent(pattern)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                if containsMediaFiles(at: folderURL) {
                    return CameraDetectionResult(
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
    do {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path.path)
        let lowercaseExtensions = extensions.map { $0.lowercased() }
        
        for item in contents {
            let itemURL = path.appendingPathComponent(item)
            let fileExtension = itemURL.pathExtension.lowercased()
            
            if lowercaseExtensions.contains(fileExtension) {
                return true
            }
            
            // Recursively check subdirectories (but limit depth to avoid performance issues)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                if containsFilesWithExtensions(at: itemURL, extensions: extensions) {
                    return true
                }
            }
        }
        
        return false
    } catch {
        return false
    }
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
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}