// Core/Model/CameraCard.swift - Shared camera card models
import Foundation

// MARK: - Detected Camera Type

enum DetectedCameraType: String, CaseIterable {
    // Professional Cinema Cameras
    case redCamera = "RED"
    case arri = "ARRI"
    case blackmagic = "Blackmagic"
    case sony = "Sony"
    case canon = "Canon"
    case panasonic = "Panasonic"
    case fujifilm = "Fujifilm"
    case nikon = "Nikon"
    
    // Action/Drone Cameras
    case gopro = "GoPro"
    case dji = "DJI"
    case insta360 = "Insta360"
    
    // Generic patterns
    case genericDCIM = "DCIM"
    case genericMedia = "Media"
    case unknown = "Unknown Camera"
    
    var displayName: String {
        switch self {
        case .redCamera: return "RED Camera"
        case .arri: return "ARRI Camera"
        case .blackmagic: return "Blackmagic Camera"
        case .sony: return "Sony Camera"
        case .canon: return "Canon Camera"
        case .panasonic: return "Panasonic Camera"
        case .fujifilm: return "Fujifilm Camera"
        case .nikon: return "Nikon Camera"
        case .gopro: return "GoPro Camera"
        case .dji: return "DJI Drone/Camera"
        case .insta360: return "Insta360 Camera"
        case .genericDCIM: return "Digital Camera (DCIM)"
        case .genericMedia: return "Media Device"
        case .unknown: return "Unknown Camera"
        }
    }
    
    var expectedFolders: [String] {
        switch self {
        case .redCamera:
            return ["RED", "REDMAG", "R3D"]
        case .arri:
            return ["ARRIRAW", "ARRI", "CLIPS"]
        case .blackmagic:
            return ["BRAW", "Blackmagic RAW"]
        case .sony:
            return ["PRIVATE", "DCIM", "XDCAM"]
        case .canon:
            return ["DCIM", "CANON"]
        case .panasonic:
            return ["DCIM", "PRIVATE"]
        case .fujifilm:
            return ["DCIM"]
        case .nikon:
            return ["DCIM"]
        case .gopro:
            return ["DCIM", "MISC"]
        case .dji:
            return ["DCIM", "DJI"]
        case .insta360:
            return ["DCIM", "Insta360"]
        case .genericDCIM:
            return ["DCIM"]
        case .genericMedia:
            return ["MEDIA", "VIDEO", "AUDIO"]
        case .unknown:
            return []
        }
    }
}

// MARK: - Camera Card Model

struct CameraCard: Identifiable {
    let id = UUID()
    let volumeURL: URL
    let cameraType: DetectedCameraType
    let mediaPath: URL  // Path to the actual media folder (e.g., /Volumes/Card/DCIM)
    let detectedAt: Date
    let volumeInfo: VolumeInfo
    
    var displayName: String {
        return "\(cameraType.displayName) - \(volumeURL.lastPathComponent)"
    }
    
    var mediaCount: Int? {
        return volumeInfo.estimatedFileCount
    }
    
    var totalSize: Int64? {
        return volumeInfo.totalSize
    }
}

// MARK: - Volume Info Model

struct VolumeInfo {
    let name: String
    let totalSize: Int64?
    let availableSize: Int64?
    let estimatedFileCount: Int?
    let fileSystem: String?
    let isRemovable: Bool
    let isEjectable: Bool
}

// MARK: - Volume Events

struct VolumeEvent {
    enum EventType {
        case mounted
        case unmounted
    }
    
    let type: EventType
    let volume: URL
    let timestamp: Date
}

// MARK: - Volume Scanner

struct VolumeScanner {
    static func getAvailableVolumes() async -> [URL] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let volumes = FileManager.default.mountedVolumeURLs(
                    includingResourceValuesForKeys: [
                        .volumeNameKey,
                        .volumeIsRemovableKey,
                        .volumeIsEjectableKey
                    ],
                    options: [.skipHiddenVolumes]
                ) ?? []
                
                continuation.resume(returning: volumes)
            }
        }
    }
    
    static func getVolumeInfo(for volume: URL) -> VolumeInfo? {
        do {
            let resourceValues = try volume.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeLocalizedFormatDescriptionKey
            ])
            
            return VolumeInfo(
                name: resourceValues.volumeName ?? volume.lastPathComponent,
                totalSize: resourceValues.volumeTotalCapacity.map(Int64.init),
                availableSize: resourceValues.volumeAvailableCapacity.map(Int64.init),
                estimatedFileCount: nil, // Will be calculated separately if needed
                fileSystem: resourceValues.volumeLocalizedFormatDescription,
                isRemovable: resourceValues.volumeIsRemovable ?? false,
                isEjectable: resourceValues.volumeIsEjectable ?? false
            )
        } catch {
            print("Failed to get volume info for \(volume.path): \(error)")
            return nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let cameraCardDetected = Notification.Name("CameraCardDetected")
    static let cameraCardRemoved = Notification.Name("CameraCardRemoved")
}