// Core/Services/CameraStructureDetector.swift - Camera file structure detection
import Foundation
import BitMatchEngine

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
        
        // One classifier decides the brand for every detection path
        // (CardLayoutClassifier; audit finding B).
        guard let detection = CardLayoutClassifier.classify(at: volume) else {
            return nil
        }
        SharedLogger.debug("CameraStructureDetector: \(detection.cameraType.rawValue) via \(detection.evidence)", category: .transfer)
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
            // Auto-select copies mediaPath, so it is always the card
            // root: a media subfolder (PRIVATE/, DCIM/) would silently
            // leave the rest of the card behind.
            mediaPath: volume
        )
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
