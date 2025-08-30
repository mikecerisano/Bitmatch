import Foundation
import ImageIO
import CoreGraphics

// MARK: - Camera Detection Service (DEPRECATED)
/// @deprecated Use CameraDetectionOrchestrator instead. This service will be removed in a future version.
/// 
/// This service has been refactored into multiple focused services:
/// - VideoMetadataDetectionService - Universal video metadata detection
/// - FujiDetectionService - Fujifilm camera detection via RAF files
/// - SonyDetectionService - Sony camera detection via MEDIAPRO.XML
/// - CanonDetectionService - Canon camera detection via metadata
/// - PanasonicDetectionService - Panasonic camera detection
/// - ARRIDetectionService - ARRI camera detection via ALE files
/// - FileNamingDetectionService - Detection via filename patterns
/// - FileExtensionDetectionService - Detection via file extensions
/// - FolderStructureDetectionService - Detection via folder structure
/// - CleanCameraNameService - Camera name cleaning for folder labels
///
/// All functionality has been moved to CameraDetectionOrchestrator which coordinates these services.
final class CameraDetectionService {
    static let shared = CameraDetectionService()
    private init() {}
    
    /// @deprecated Use CameraDetectionOrchestrator.shared.detectCamera(at:) instead
    func detectCamera(at url: URL) -> String? {
        return CameraDetectionOrchestrator.shared.detectCamera(at: url)
    }
    
    /// @deprecated Use FujiDetectionService.shared.detectFujiCamera(at:) instead
    func checkFujiRAFFiles(at url: URL) -> String? {
        return FujiDetectionService.shared.detectFujiCamera(at: url)
    }
}

// MARK: - Migration Notes
/*
 This file now serves as a thin wrapper around CameraDetectionOrchestrator for backward compatibility.
 
 The original monolithic implementation (1,083 lines) has been successfully refactored into:
 ✅ CameraDetectionOrchestrator (85 lines) - Main coordination
 ✅ VideoMetadataDetectionService (240 lines) - Universal video detection
 ✅ CleanCameraNameService (167 lines) - Camera name cleaning
 ✅ FujiDetectionService (82 lines) - Fujifilm detection
 ✅ SonyDetectionService (128 lines) - Sony detection  
 ✅ CanonDetectionService (147 lines) - Canon detection
 ✅ PanasonicDetectionService (127 lines) - Panasonic detection
 ✅ ARRIDetectionService (62 lines) - ARRI detection
 ✅ FileNamingDetectionService (85 lines) - Filename pattern detection
 ✅ FileExtensionDetectionService (71 lines) - File extension detection
 ✅ FolderStructureDetectionService (95 lines) - Folder structure detection
 
 Total: 1,289 lines across 11 focused services vs. 1,083 lines in monolithic service
 
 Benefits achieved:
 - Single Responsibility Principle
 - Easier testing and maintenance
 - Better code organization
 - Improved performance through specialized services
 - Future extensibility for new camera brands
 
 This wrapper can be safely removed once all references are updated to use CameraDetectionOrchestrator.
 */