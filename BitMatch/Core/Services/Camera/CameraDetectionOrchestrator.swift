// Core/Services/Camera/CameraDetectionOrchestrator.swift
import Foundation

/// Main orchestrator for camera detection using hierarchical detection methods
final class CameraDetectionOrchestrator {
    static let shared = CameraDetectionOrchestrator()
    private init() {}
    
    // MARK: - Detection Services
    private let videoDetection = VideoMetadataDetectionService.shared
    private let cleanNaming = CleanCameraNameService.shared
    private let fujiDetection = FujiDetectionService.shared
    private let sonyDetection = SonyDetectionService.shared
    private let canonDetection = CanonDetectionService.shared
    private let panasonicDetection = PanasonicDetectionService.shared
    private let arriDetection = ARRIDetectionService.shared
    private let fileNamingDetection = FileNamingDetectionService.shared
    private let fileExtensionDetection = FileExtensionDetectionService.shared
    private let folderStructureDetection = FolderStructureDetectionService.shared
    private let xmlMetadataDetection = XMLMetadataDetectionService.shared
    private let mediaMetadataDetection = MediaMetadataDetectionService.shared
    
    // MARK: - Public Interface
    
    /// Detect camera with full hierarchy of methods
    func detectCamera(at url: URL) -> String? {
        // Try detection methods in order of reliability
        if let videoInfo = videoDetection.detectCameraFromVideo(at: url) { return videoInfo }
        if let fujiInfo = fujiDetection.detectFujiCamera(at: url) { return fujiInfo }
        if let sonyInfo = sonyDetection.detectSonyCamera(at: url) { return sonyInfo }
        if let canonInfo = canonDetection.detectCanonCamera(at: url) { return canonInfo }
        if let panasonicInfo = panasonicDetection.detectPanasonicCamera(at: url) { return panasonicInfo }
        if let arriInfo = arriDetection.detectARRICamera(at: url) { return arriInfo }
        if let folderInfo = folderStructureDetection.detectCameraFromStructure(at: url) { return folderInfo }
        if let nameInfo = fileNamingDetection.detectCameraFromNaming(at: url) { return nameInfo }
        if let extInfo = fileExtensionDetection.detectCameraFromExtensions(at: url) { return extInfo }
        if let xmlInfo = xmlMetadataDetection.detectCameraFromXML(at: url) { return xmlInfo }
        if let mediaInfo = mediaMetadataDetection.detectCameraFromMedia(at: url) { return mediaInfo }
        
        return nil
    }
    
    /// Get clean camera name for folder labeling
    func getCleanCameraName(from fullCameraName: String) -> String {
        return cleanNaming.getCleanCameraName(from: fullCameraName)
    }
    
}

// MARK: - Migration Notes
/*
 This orchestrator represents the refactoring of the monolithic CameraDetectionService.
 
 Completed:
 ✅ VideoMetadataDetectionService - Universal video metadata detection
 ✅ CleanCameraNameService - Camera name cleaning for folder labels
 ✅ FujiDetectionService - RAF file detection and metadata extraction
 ✅ SonyDetectionService - MEDIAPRO.XML and folder structure detection
 ✅ CanonDetectionService - Canon metadata and RAW file detection
 ✅ PanasonicDetectionService - Panasonic metadata and folder structure
 ✅ ARRIDetectionService - ALE file detection and metadata extraction
 ✅ FileNamingDetectionService - Camera detection via filename patterns
 ✅ FileExtensionDetectionService - Camera detection via file extensions
 ✅ FolderStructureDetectionService - Camera detection via directory structure
 
 ✅ XMLMetadataDetectionService - Generic XML metadata detection
 ✅ MediaMetadataDetectionService - Generic media file metadata detection
 
 Migration Complete:
 🎉 All detection methods now implemented in focused services
 🎉 Original CameraDetectionService reduced to thin compatibility wrapper
 🎉 Full modular architecture achieved
 
 This approach ensures:
 - Single Responsibility Principle
 - Easy testing of individual detection methods  
 - Cleaner code organization
 - Better maintainability as we add more cameras
 */