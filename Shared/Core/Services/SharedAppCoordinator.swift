// SharedAppCoordinator.swift - Platform-agnostic app coordination
import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
class SharedAppCoordinator: ObservableObject {
    
    // MARK: - Platform Manager
    private let platformManager: PlatformManager
    
    // MARK: - Published State
    @Published var currentMode: AppMode = .copyAndVerify
    @Published var verificationMode: VerificationMode = .standard
    @Published var cameraLabelSettings = CameraLabelSettings()
    @Published var reportSettings = ReportPrefs()
    
    // MARK: - Operation State
    @Published var isOperationInProgress = false
    @Published var operationState: OperationState = .notStarted
    @Published var progress: OperationProgress?
    @Published var results: [ResultRow] = []
    @Published var currentOperation: FileOperation?
    
    // MARK: - File Selection State
    @Published var sourceURL: URL?
    @Published var destinationURLs: [URL] = []
    @Published var leftURL: URL? // For folder comparison
    @Published var rightURL: URL? // For folder comparison
    
    // MARK: - Camera Detection State
    @Published var detectedCamera: CameraCard?
    @Published var cameraDetectionInProgress = false
    
    // MARK: - Folder Info State
    @Published var sourceFolderInfo: FolderInfo?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(platformManager: PlatformManager) {
        self.platformManager = platformManager
        setupBindings()
    }
    
    #if os(iOS)
    convenience init() {
        self.init(platformManager: IOSPlatformManager.shared)
    }
    #endif
    
    #if os(macOS)
    convenience init() {
        self.init(platformManager: MacOSPlatformManager.shared)
    }
    #endif
    
    private func setupBindings() {
        // Monitor source URL changes for camera detection and folder info
        $sourceURL
            .sink { [weak self] url in
                Task { @MainActor in
                    if let url = url {
                        await self?.detectCameraFromSource(url)
                        await self?.updateSourceFolderInfo(url)
                    } else {
                        self?.sourceFolderInfo = nil
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - File Selection Methods
    
    func selectSourceFolder() async {
        sourceURL = await platformManager.fileSystem.selectSourceFolder()
    }
    
    func addDestinationFolder() async {
        let urls = await platformManager.fileSystem.selectDestinationFolders()
        for url in urls {
            if !destinationURLs.contains(url) {
                destinationURLs.append(url)
            }
        }
    }
    
    func removeDestinationFolder(_ url: URL) {
        destinationURLs.removeAll { $0 == url }
    }
    
    func selectLeftFolder() async {
        leftURL = await platformManager.fileSystem.selectLeftFolder()
    }
    
    func selectRightFolder() async {
        rightURL = await platformManager.fileSystem.selectRightFolder()
    }
    
    // MARK: - Operation Control
    
    func startOperation() async {
        guard !isOperationInProgress else { return }
        guard let sourceURL = sourceURL, !destinationURLs.isEmpty else {
            await platformManager.presentAlert(
                title: "Invalid Selection", 
                message: "Please select a source folder and at least one destination folder."
            )
            return
        }
        
        isOperationInProgress = true
        operationState = .inProgress
        results = []
        progress = nil
        print("🔘 Operation started - isInProgress: \(isOperationInProgress)")
        
        // Check if we're using fake data (URLs pointing to /Volumes that don't exist)
        let isFakeData = sourceURL.path.starts(with: "/Volumes/") && !FileManager.default.fileExists(atPath: sourceURL.path)
        
        if isFakeData {
            // Simulate fake operation for development testing
            await simulateFakeOperation(
                sourceURL: sourceURL,
                destinationURLs: destinationURLs
            )
        } else {
            // Perform real file operations
            do {
                let operation = try await platformManager.fileOperations.performFileOperation(
                    sourceURL: sourceURL,
                    destinationURLs: destinationURLs,
                    verificationMode: verificationMode,
                    settings: cameraLabelSettings
                ) { [weak self] progressUpdate in
                    Task { @MainActor in
                        self?.progress = progressUpdate
                    }
                }
                
                currentOperation = operation
                operationState = .completed
                
                // Convert results
                results = operation.results.map { fileResult in
                    ResultRow(
                        path: fileResult.sourceURL.path,
                        status: fileResult.statusDescription,
                        size: fileResult.fileSize,
                        checksum: fileResult.verificationResult?.sourceChecksum
                    )
                }
                
            } catch {
                operationState = .failed
                await platformManager.presentError(error)
            }
        }
        
        isOperationInProgress = false
        print("🔘 Operation ended - isInProgress: \(isOperationInProgress)")
    }
    
    func cancelOperation() {
        platformManager.fileOperations.cancelOperation()
        isOperationInProgress = false
        operationState = .cancelled
    }
    
    func pauseOperation() async {
        await platformManager.fileOperations.pauseOperation()
    }
    
    func resumeOperation() async {
        await platformManager.fileOperations.resumeOperation()
    }
    
    // MARK: - Fake Operation Simulation
    
    private func simulateFakeOperation(sourceURL: URL, destinationURLs: [URL]) async {
        print("🎭 Starting fake operation simulation")
        print("🎭 isOperationInProgress at start: \(isOperationInProgress)")
        
        // Get total file count from fake source info (reduced for easier debugging)
        let sourceFileCount = sourceFolderInfo?.fileCount ?? 0
        let totalFiles = sourceFileCount > 0 ? min(sourceFileCount, 20) : 20 // Max 20 files for demo
        print("🎭 Source has \(sourceFileCount) files, will process \(totalFiles) files")
        
        do {
            // Simulate copy phase
            operationState = .inProgress
            
            for i in 0..<totalFiles {
                // Check if operation was cancelled
                guard isOperationInProgress else { break }
                
                // Simulate file processing time (slower for demo visibility)
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms per file for better demo
                
                // Generate fake file names
                let fakeFileName = "DSC\(String(format: "%05d", i+1)).ARW"
                let fileSize = Int64.random(in: 25_000_000...85_000_000) // 25-85 MB
                
                // Update progress
                let progressValue = Double(i + 1) / Double(totalFiles)
                let currentProgress = OperationProgress(
                    overallProgress: progressValue,
                    currentFile: fakeFileName,
                    filesProcessed: i + 1,
                    totalFiles: totalFiles,
                    currentStage: i < totalFiles / 2 ? .copying : .verifying,
                    speed: Double.random(in: 50_000_000...150_000_000), // 50-150 MB/s
                    timeRemaining: Double(totalFiles - i - 1) * 0.05
                )
                
                await MainActor.run {
                    progress = currentProgress
                    print("🎭 Updated progress: \(Int(progressValue * 100))% - \(fakeFileName)")
                }
                
                // Generate fake results (99% success)
                if i % 20 == 0 { // Add result every 20 files
                    let result = ResultRow(
                        path: fakeFileName,
                        status: Double.random(in: 0...1) < 0.99 ? "✓ Verified" : "⚠ Warning",
                        size: fileSize,
                        checksum: String(format: "%08x", Int.random(in: 0...Int.max))
                    )
                    await MainActor.run {
                        results.append(result)
                    }
                }
                
                print("🎭 Fake progress: \(i+1)/\(totalFiles) - \(fakeFileName)")
            }
            
            // Final completion
            await MainActor.run {
                operationState = .completed
                print("🎭 Fake operation completed successfully")
            }
            
        } catch {
            await MainActor.run {
                operationState = .failed
                print("🎭 Fake operation cancelled")
            }
        }
    }
    
    // MARK: - Camera Detection
    
    private func detectCameraFromSource(_ url: URL) async {
        cameraDetectionInProgress = true
        detectedCamera = nil
        
        let result = await platformManager.cameraDetection.detectCamera(from: url)
        
        detectedCamera = result.cameraCard
        cameraDetectionInProgress = false
        
        // Update camera label settings if we detected a camera
        if let camera = result.cameraCard, result.confidence > 0.8 {
            if cameraLabelSettings.label.isEmpty {
                cameraLabelSettings.label = camera.name
            }
        }
    }
    
    // MARK: - Folder Info Updates
    
    private func updateSourceFolderInfo(_ url: URL) async {
        sourceFolderInfo = await getFolderInfo(for: url)
    }
    
    // Simple folder info helper for shared coordinator
    private func getFolderInfo(for url: URL) async -> FolderInfo? {
        var fileCount = 0
        var totalSize: Int64 = 0
        
        let fileEnumKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: fileEnumKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        
        while let file = enumerator.nextObject() {
            guard let fileURL = file as? URL else { continue }
            guard let rv = try? fileURL.resourceValues(forKeys: Set(fileEnumKeys)) else { continue }
            if rv.isSymbolicLink == true { continue }
            if rv.isRegularFile == true {
                fileCount += 1
                totalSize += Int64(rv.fileSize ?? 0)
            }
        }
        
        // Get the last modified date
        let lastModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        
        return FolderInfo(
            url: url,
            fileCount: fileCount,
            totalSize: totalSize,
            lastModified: lastModified
        )
    }
    
    // MARK: - Folder Comparison (for Compare mode)
    
    func compareFolders() async {
        guard currentMode == .compareFolders else { return }
        guard let _ = leftURL, let _ = rightURL else {
            await platformManager.presentAlert(
                title: "Invalid Selection",
                message: "Please select both folders to compare."
            )
            return
        }
        
        isOperationInProgress = true
        operationState = .inProgress
        
        // TODO: Implement folder comparison logic
        // This would analyze differences between two folders
        
        isOperationInProgress = false
        operationState = .completed
    }
    
    // MARK: - Report Generation
    
    func generateReport() async {
        guard currentOperation != nil else {
            await platformManager.presentAlert(
                title: "No Operation Data",
                message: "Please complete a file operation before generating a report."
            )
            return
        }
        
        // TODO: Implement report generation using reportSettings
        await platformManager.presentAlert(
            title: "Report Generated",
            message: "Report generation feature coming soon!"
        )
    }
    
    // MARK: - Computed Properties
    
    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify:
            return sourceURL != nil && !destinationURLs.isEmpty && !isOperationInProgress
        case .compareFolders:
            return leftURL != nil && rightURL != nil && !isOperationInProgress
        case .masterReport:
            return currentOperation != nil && !isOperationInProgress
        }
    }
    
    var progressPercentage: Double {
        return progress?.overallProgress ?? 0.0
    }
    
    var formattedSpeed: String? {
        return progress?.formattedSpeed
    }
    
    var formattedTimeRemaining: String? {
        return progress?.formattedTimeRemaining
    }
    
    var currentStage: ProgressStage {
        return progress?.currentStage ?? .idle
    }
}