// ServiceProtocols.swift - Platform-agnostic service interfaces
import Foundation
import BitMatchEngine

// MARK: - File System Service Protocol (app)

/// File access plus the platform's folder pickers.
protocol FileSystemService: FileAccess {
    func selectSourceFolder() async -> URL?
    func selectDestinationFolders() async -> [URL]
    func selectLeftFolder() async -> URL?
    func selectRightFolder() async -> URL?
}

// MARK: - Camera Detection Service Protocol
protocol CameraDetectionService: Sendable {
    func detectCamera(from folderURL: URL) async -> CameraDetectionResult
    func analyzeFolderStructure(at url: URL) async throws -> [String: Any]
    func extractVideoMetadata(from fileURL: URL) async throws -> [String: Any]
    func parseXMLMetadata(from fileURL: URL) async throws -> [String: Any]
}

// MARK: - Platform Manager Protocol
protocol PlatformManager: Sendable {
    nonisolated var fileSystem: FileSystemService { get }
    nonisolated var checksum: ChecksumService { get }
    nonisolated var fileOperations: FileOperationsService { get }
    nonisolated var cameraDetection: CameraDetectionService { get }
    nonisolated var supportsDragAndDrop: Bool { get }
    
    func presentAlert(title: String, message: String) async
    func presentError(_ error: Error) async
    func openURL(_ url: URL) async -> Bool
    
}
