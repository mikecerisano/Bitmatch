// Core/ViewModels/FileSelectionViewModel+Platform.swift
// Platform-aware extensions for FileSelectionViewModel

import Foundation
import SwiftUI
import Combine

extension FileSelectionViewModel {
    
    // MARK: - Platform-Aware File Selection
    
    /// Select source folder using platform-appropriate picker
    func selectSourceFolder() async {
        guard let url = await PlatformManager.shared.fileSystem.selectSourceFolder() else {
            return
        }
        
        // Handle security-scoped access for iOS
        if PlatformManager.shared.requiresSecurityScopedAccess {
            _ = url.startAccessingSecurityScopedResource()
        }
        
        sourceURL = url
    }
    
    /// Select destination folders using platform-appropriate picker
    func selectDestinationFolders() async {
        let urls = await PlatformManager.shared.fileSystem.selectDestinationFolders()
        
        // Handle security-scoped access for iOS
        if PlatformManager.shared.requiresSecurityScopedAccess {
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
            }
        }
        
        destinationURLs = urls
    }
    
    /// Select left folder for comparison (platform-aware)
    func selectLeftFolder() async {
        guard let url = await PlatformManager.shared.fileSystem.selectSourceFolder() else {
            return
        }
        
        if PlatformManager.shared.requiresSecurityScopedAccess {
            _ = url.startAccessingSecurityScopedResource()
        }
        
        leftURL = url
    }
    
    /// Select right folder for comparison (platform-aware)
    func selectRightFolder() async {
        let urls = await PlatformManager.shared.fileSystem.selectDestinationFolders()
        guard let url = urls.first else {
            return
        }
        
        if PlatformManager.shared.requiresSecurityScopedAccess {
            _ = url.startAccessingSecurityScopedResource()
        }
        
        rightURL = url
    }
    
    // MARK: - Platform-Aware Volume Information
    
    /// Get volume info using platform services
    func getVolumeInfo(for url: URL) -> PlatformVolumeInfo? {
        return PlatformManager.shared.fileSystem.getVolumeInfo(for: url)
    }
    
    /// Check available space using platform services
    func getAvailableSpace(for url: URL) -> Int64? {
        return PlatformManager.shared.fileSystem.getAvailableSpace(at: url)
    }
    
    // MARK: - Platform Capabilities
    
    var supportsDragAndDrop: Bool {
        PlatformManager.shared.supportsDragAndDrop
    }
    
    var supportsVolumeMonitoring: Bool {
        PlatformManager.shared.supportsVolumeMonitoring
    }
    
    var supportsMultipleDestinations: Bool {
        PlatformManager.shared.supportsMultipleDestinations
    }
}