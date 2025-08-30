// Core/Services/Platform/PlatformManager.swift
import Foundation

/// Provides platform-appropriate services
final class PlatformManager {
    static let shared = PlatformManager()
    private init() {}
    
    // MARK: - Service Providers
    
    var fileSystem: FileSystemService {
        #if os(macOS)
        return MacOSFileSystemService.shared
        #else
        return IOSFileSystemService.shared
        #endif
    }
    
    var systemIntegration: SystemIntegrationService {
        #if os(macOS)
        return MacOSSystemIntegrationService.shared
        #else
        return IOSSystemIntegrationService.shared
        #endif
    }
    
    // MARK: - Platform Info
    
    var currentPlatform: Platform {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }
    
    var supportsMultipleDestinations: Bool {
        // Both platforms support multiple destinations, but iOS is more limited
        return true
    }
    
    var supportsDragAndDrop: Bool {
        #if os(macOS)
        return true
        #else
        return false // iOS document picker instead
        #endif
    }
    
    var supportsVolumeMonitoring: Bool {
        #if os(macOS)
        return true
        #else
        return false // iOS has very limited volume monitoring
        #endif
    }
    
    var requiresSecurityScopedAccess: Bool {
        #if os(macOS)
        return false
        #else
        return true // iOS requires security-scoped access for external files
        #endif
    }
}

enum Platform {
    case macOS
    case iOS
    
    var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .iOS: return "iPadOS"
        }
    }
}