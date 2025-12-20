// DevModeManager.swift - Development mode testing utilities
import Foundation
import Combine
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

class DevModeManager: ObservableObject {
    static let shared = DevModeManager()
    
    @Published var isDevModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isDevModeEnabled, forKey: "DevModeEnabled")
            AppLogger.devMode("Mode \(isDevModeEnabled ? "ENABLED" : "DISABLED")")
        }
    }
    
    // Controls whether verbose dev logs are printed from subsystems (e.g., volume scanning)
    @Published var verboseLogs: Bool = false {
        didSet {
            UserDefaults.standard.set(verboseLogs, forKey: "VerboseDevLogs")
        }
    }
    
    private init() {
        self.isDevModeEnabled = UserDefaults.standard.bool(forKey: "DevModeEnabled")
        self.verboseLogs = UserDefaults.standard.bool(forKey: "VerboseDevLogs")
    }
    
    private var stressCancellables = Set<AnyCancellable>()
    
    // MARK: - Fake Data Generation
    
    
    func generateFakeSource() -> (url: URL, info: FolderInfo) {
        let cameras = ["A_CAM", "B_CAM", "C_CAM", "MAIN_CAM", "BACKUP_CAM"]
        let selectedCamera = cameras.randomElement()!
        
        // Realistic camera models with their typical file patterns
        let cameraModels = [
            ("Sony A7S III", ["C0001", "C0002", "C0003"], ["MP4", "XML"]),
            ("Sony FX6", ["A001_C001", "A001_C002", "A002_C001"], ["MOV", "XML"]),
            ("Canon R5C", ["MVI_", "IMG_"], ["MOV", "CR3", "JPG"]),
            ("ARRI Alexa Mini", ["A001_C001", "A002_C001"], ["MOV", "ARI"]),
            ("RED Komodo", ["A001_C001", "A002_C001"], ["R3D", "MOV"]),
            ("Blackmagic Pocket 6K", ["BMPCC", "Clip_"], ["MOV", "BRAW"]),
            ("Panasonic GH6", ["P", "DSC"], ["MOV", "MP4", "RW2"]),
            ("Canon C70", ["MVI_", "Canon_"], ["MP4", "MOV"])
        ]
        
        _ = cameraModels.randomElement()!
        
        // Just create fake URL - no actual directory needed for UI testing
        let fakeURL = URL(fileURLWithPath: "/Volumes/\(selectedCamera)")
        let fileCount = Int.random(in: 150...450)
        let totalSize = Int64.random(in: 2_000_000_000...8_000_000_000) // 2-8 GB
        
        #if os(macOS)
        let cameraIcon = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil) ?? NSImage()
        #else
        let cameraIcon = UIImage(systemName: "camera.fill") ?? UIImage()
        #endif
        
        let fakeInfo = FolderInfo(
            url: fakeURL,
            fileCount: fileCount,
            totalSize: totalSize,
            lastModified: Date(),
            isInternalDrive: false
        )
        
        return (fakeURL, fakeInfo)
    }
    
    func generateFakeDestinations() -> [(url: URL, info: FolderInfo)] {
        let destinations = [
            ("Samsung T7 NVMe", Int64.random(in: 500_000_000_000...2_000_000_000_000)), // 500GB-2TB
            ("WD Black SSD", Int64.random(in: 250_000_000_000...1_000_000_000_000)),    // 250GB-1TB  
            ("Seagate Backup", Int64.random(in: 1_000_000_000_000...4_000_000_000_000)), // 1TB-4TB
            ("LaCie HDD", Int64.random(in: 2_000_000_000_000...8_000_000_000_000))      // 2TB-8TB
        ]
        
        let selectedCount = Int.random(in: 2...4)
        return destinations.prefix(selectedCount).map { name, capacity in
            // Just create fake URL - no actual directory needed for UI testing
            let fakeURL = URL(fileURLWithPath: "/Volumes/\(name)")
            
            #if os(macOS)
            let driveIcon = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil) ?? NSImage()
            #else
            let driveIcon = UIImage(systemName: "externaldrive.fill") ?? UIImage()
            #endif
            
            let fakeInfo = FolderInfo(
                url: fakeURL,
                fileCount: 0, // Destinations start empty
                totalSize: capacity,
                lastModified: Date(),
                isInternalDrive: false
            )
            return (fakeURL, fakeInfo)
        }
    }
    
    // MARK: - Fake Data Population
    
    #if os(macOS)
    enum StressPreset { case small, medium, large }

    @MainActor
    func runStressTest(coordinator: AppCoordinator, preset: StressPreset, verify: Bool = false, cleanupAfter: Bool = true) {
        guard isDevModeEnabled else {
            SharedLogger.debug("Stress test skipped: Dev Mode disabled")
            return
        }
        guard !coordinator.isOperationInProgress else {
            SharedLogger.debug("Stress test skipped: operation already in progress")
            return
        }
        
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let src = tmp.appendingPathComponent("bitmatch_stress_src_\(UUID().uuidString)", isDirectory: true)
        let dst = tmp.appendingPathComponent("bitmatch_stress_dst_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: src, withIntermediateDirectories: true)
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        } catch {
            SharedLogger.error("Failed to create temp dirs: \(error)")
            return
        }
        
        // Preset configurations targeting approximate totals: ~10MB, ~100MB, ~300MB
        let dirCount: Int
        let filesPerDir: Int
        let smallSize = 4 * 1024 // 4KB tiny files
        let largeFiles: Int
        let largeSize: Int
        switch preset {
        case .small:
            dirCount = 20; filesPerDir = 50; largeFiles = 4; largeSize = 1 * 1024 * 1024 // ~3.8MB + 4MB
        case .medium:
            dirCount = 40; filesPerDir = 200; largeFiles = 70; largeSize = 1 * 1024 * 1024 // ~32MB + 70MB
        case .large:
            dirCount = 60; filesPerDir = 300; largeFiles = 230; largeSize = 1 * 1024 * 1024 // ~70MB + 230MB
        }
        let estimatedBytes = Int64(dirCount * filesPerDir * smallSize + largeFiles * largeSize)
        SharedLogger.info("Preparing synthetic dataset (~\(ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file))) …")
        
        // Generate files off the main thread
        Task.detached(priority: .userInitiated) {
            var dataSmall = Data(count: smallSize)
            var dataLarge = Data(count: largeSize)
            // Fill with a simple pattern to avoid compressible zeros
            dataSmall.withUnsafeMutableBytes { buf in
                for i in 0..<buf.count { buf[i] = UInt8(truncatingIfNeeded: i) }
            }
            dataLarge.withUnsafeMutableBytes { buf in
                for i in 0..<buf.count { buf[i] = UInt8(truncatingIfNeeded: i & 0xFF) }
            }
            
            let fm = FileManager.default
            // Create directories and small files
            for d in 1...dirCount {
                let dirURL = src.appendingPathComponent(String(format: "dir%03d", d), isDirectory: true)
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                for f in 1...filesPerDir {
                    let fileURL = dirURL.appendingPathComponent(String(format: "file%04d.bin", f))
                    try? dataSmall.write(to: fileURL, options: .atomic)
                }
            }
            // Add a handful of larger files at root
            for i in 1...largeFiles {
                let f = src.appendingPathComponent(String(format: "large%03d.bin", i))
                try? dataLarge.write(to: f, options: .atomic)
            }
            
            await MainActor.run {
                // Wire up coordinator selections
                coordinator.fileSelectionViewModel.sourceURL = src
                coordinator.fileSelectionViewModel.sourceFolderInfo = FolderInfo(
                    url: src,
                    fileCount: dirCount * filesPerDir + largeFiles,
                    totalSize: estimatedBytes,
                    lastModified: Date(),
                    isInternalDrive: true
                )
                coordinator.fileSelectionViewModel.destinationURLs = [dst]
                coordinator.verificationMode = verify ? .standard : .quick
                coordinator.switchMode(to: .copyAndVerify)
                
                // Subscribe for cleanup on completion/cancel
                self.stressCancellables.removeAll()
                coordinator.operationViewModel.$state
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] state in
                        guard let self = self else { return }
                        switch state {
                        case .completed, .failed, .cancelled:
                            if cleanupAfter { self.cleanupSynthetic(at: src, and: dst) }
                            self.stressCancellables.removeAll()
                        default:
                            break
                        }
                    }
                    .store(in: &self.stressCancellables)
                // Also observe shared-core completion broadcast
                NotificationCenter.default.publisher(for: .operationCompleted)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self = self else { return }
                        if cleanupAfter { self.cleanupSynthetic(at: src, and: dst) }
                        self.stressCancellables.removeAll()
                    }
                    .store(in: &self.stressCancellables)
                NotificationCenter.default.publisher(for: .operationCancelledByUser)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self = self else { return }
                        if cleanupAfter { self.cleanupSynthetic(at: src, and: dst) }
                        self.stressCancellables.removeAll()
                    }
                    .store(in: &self.stressCancellables)
                
                // Start the transfer
                coordinator.startOperation()
            }
        }
    }

    // Backwards compatibility shim for prior call sites
    @MainActor
    func runStressTest(coordinator: AppCoordinator, smallFootprint: Bool = true) {
        let preset: StressPreset = smallFootprint ? .small : .medium
        runStressTest(coordinator: coordinator, preset: preset, verify: false, cleanupAfter: true)
    }
    
    @MainActor
    private func cleanupSynthetic(at src: URL, and dst: URL) {
        SharedLogger.info("Cleaning up synthetic data…")
        let fm = FileManager.default
        try? fm.removeItem(at: src)
        try? fm.removeItem(at: dst)
        SharedLogger.info("Cleanup complete.")
    }
    
    @MainActor func fillTestDataOnly(coordinator: AppCoordinator) {
        SharedLogger.debug("Fill Test Data called - Dev Mode: \(isDevModeEnabled)")
        
        let (sourceURL, sourceInfo) = generateFakeSource()
        let destinations = generateFakeDestinations()
        
        // Set fake source
        coordinator.fileSelectionViewModel.sourceURL = sourceURL
        coordinator.fileSelectionViewModel.sourceFolderInfo = sourceInfo
        
        // Set fake destinations
        coordinator.fileSelectionViewModel.destinationURLs = destinations.map { $0.url }

        // Simulate folder info loading for destinations
        for (index, (_, info)) in destinations.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                // We can't easily set individual destination info, so we'll just log it
                SharedLogger.debug("Fake destination \(index): \(info.formattedSize)")
            }
        }

        // Switch to copy mode but don't start operation
        coordinator.switchMode(to: .copyAndVerify)
    }
    #endif
    
    // MARK: - iPad Test Data Population
    
    #if os(iOS)
    @MainActor func fillTestDataOnly(sourceFolder: inout URL?, destinationFolders: inout [URL]) {
        SharedLogger.debug("Fill Test Data called for iPad - Dev Mode: \(isDevModeEnabled)")
        
        let (sourceURL, sourceInfo) = generateFakeSource()
        let destinations = generateFakeDestinations()
        
        // Set fake source
        sourceFolder = sourceURL
        
        // Set fake destinations
        destinationFolders = destinations.map { $0.url }

        SharedLogger.debug("Fake source: \(sourceInfo.name) - \(sourceInfo.formattedSize)")
        for (index, (_, info)) in destinations.enumerated() {
            SharedLogger.debug("Fake destination \(index): \(info.name) - \(info.formattedSize)")
        }
    }
    
    // MARK: - Shared Coordinator Test Data Population (for iPad)
    
    @MainActor func fillTestDataOnly(coordinator: SharedAppCoordinator) {
        SharedLogger.debug("Fill Test Data called for SharedAppCoordinator - Dev Mode: \(isDevModeEnabled)")

        guard isDevModeEnabled else {
            SharedLogger.debug("Dev mode is disabled, not filling fake data")
            return
        }
        
        let (sourceURL, sourceInfo) = generateFakeSource()
        let destinations = generateFakeDestinations()
        
        // Set fake source
        coordinator.sourceURL = sourceURL
        coordinator.sourceFolderInfo = sourceInfo
        SharedLogger.debug("Set source URL: \(sourceURL)")
        SharedLogger.debug("Source URL is now: \(coordinator.sourceURL?.path ?? "nil")")

        // Set fake destinations
        coordinator.destinationURLs = destinations.map { $0.url }
        SharedLogger.debug("Set \(destinations.count) destinations")
        SharedLogger.debug("Destinations are now: \(coordinator.destinationURLs.map { $0.path })")
        
        // Set fake camera detection
        let cameraName = "Sony A7S III"
        coordinator.detectedCamera = CameraCard(
            name: cameraName,
            manufacturer: "Sony",
            model: "A7S III",
            fileCount: sourceInfo.fileCount,
            totalSize: sourceInfo.totalSize,
            detectionConfidence: 0.95,
            metadata: [
                "volumeName": sourceURL.lastPathComponent,
                "path": sourceURL.path
            ]
        )

        SharedLogger.debug("Fake source: \(sourceInfo.name) - \(sourceInfo.formattedSize)")
        for (index, (_, info)) in destinations.enumerated() {
            SharedLogger.debug("Fake destination \(index): \(info.name) - \(info.formattedSize)")
        }
    }
    #endif
    
    // MARK: - Fake Transfer Simulation (for manual testing)
    
    #if os(macOS)
    @MainActor func startFakeTransfer(coordinator: AppCoordinator) {
        SharedLogger.info("Starting fake transfer simulation")
        
        let (sourceURL, sourceInfo) = generateFakeSource()
        let destinations = generateFakeDestinations()
        
        // Set fake source
        coordinator.fileSelectionViewModel.sourceURL = sourceURL
        coordinator.fileSelectionViewModel.sourceFolderInfo = sourceInfo
        
        // Set fake destinations
        coordinator.fileSelectionViewModel.destinationURLs = destinations.map { $0.url }

        // Simulate folder info loading for destinations
        for (index, (_, info)) in destinations.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                // We can't easily set individual destination info, so we'll just log it
                SharedLogger.debug("Fake destination \(index): \(info.formattedSize)")
            }
        }

        // Start the actual transfer after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            coordinator.switchMode(to: .copyAndVerify)
            coordinator.startOperation()
        }
    }
    
    @MainActor func addFakeQueueItem(coordinator: AppCoordinator) {
        SharedLogger.debug("Add Fake Queue Item called - Dev Mode: \(isDevModeEnabled)")
        let (sourceURL, sourceInfo) = generateFakeSource()
        let destinations = generateFakeDestinations()

        SharedLogger.debug("Queuing: \(sourceURL.lastPathComponent) → \(destinations.count) destinations")
        for (destURL, _) in destinations {
            SharedLogger.debug("   → \(destURL.lastPathComponent)")
        }
        
        // Post notification that the queue system will handle
        NotificationCenter.default.post(
            name: .fakeTransferQueued,
            object: nil,
            userInfo: [
                "source": sourceURL,
                "sourceInfo": sourceInfo,
                "destinations": destinations.map { $0.url }
            ]
        )
    }
    
    @MainActor func simulateQueueProgression(coordinator: AppCoordinator) {
        // Simulate moving queued transfers to active and completed states
        guard coordinator.isOperationInProgress else { return }

        SharedLogger.debug("Simulating queue progression...")
        
        // In a real implementation, this would be handled by the operation system
        // For now, we just post notifications to simulate the progression
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NotificationCenter.default.post(name: .simulateTransferCompletion, object: nil)
        }
    }
    #endif
}

// MARK: - Fake Transfer Progress Simulation

extension DevModeManager {
    
    #if os(macOS)
    @MainActor func simulateRealisticTransferProgress(coordinator: AppCoordinator) {
        // This will be called during fake transfers to provide realistic progress updates
        // The actual FileOperationsService will handle the fake progress in dev mode
        
        guard coordinator.isOperationInProgress else { return }
        
        let totalFiles = coordinator.progressViewModel.fileCountTotal
        let filesPerSecond: Double = 2.5 // Realistic speed for large video files
        let totalDurationSeconds = Double(totalFiles) / filesPerSecond

        SharedLogger.debug("Simulating transfer: \(totalFiles) files over \(String(format: "%.1f", totalDurationSeconds))s")
    }
    #endif
    
    // MARK: - Fake Progress Simulation
    
    @MainActor
    static func simulateFakeCopyProgress(
        totalFiles: Int,
        onProgress: @escaping @MainActor (String, Int64) -> Void,
        onError: @escaping @MainActor (String, Error) -> Void
    ) async throws {
        
        // Calculate timing to make the transfer last exactly 1 minute
        let targetDurationSeconds: Double = 60.0 // 1 minute
        let filesPerSecond = Double(totalFiles) / targetDurationSeconds
        let interval = 1.0 / filesPerSecond

        SharedLogger.debug("Fake transfer will take \(targetDurationSeconds)s for \(totalFiles) files (\(String(format: "%.2f", filesPerSecond)) files/sec)")
        
        let fakeFileNames = [
            "DSC00001.ARW", "DSC00002.ARW", "DSC00003.ARW", "DSC00004.ARW", "DSC00005.ARW",
            "C0001.MP4", "C0002.MP4", "C0003.MP4", "C0004.MP4", "C0005.MP4",
            "DSC00006.JPG", "DSC00007.JPG", "DSC00008.JPG", "DSC00009.JPG", "DSC00010.JPG",
            "A001_C001_230825_R4K8.MOV", "A001_C002_230825_R4K8.MOV", "A001_C003_230825_R4K8.MOV",
            "PROXY001.MP4", "PROXY002.MP4", "PROXY003.MP4",
            "AUDIO_CH1.WAV", "AUDIO_CH2.WAV", "SYNC_DATA.XML", "METADATA.XML"
        ]
        
        for i in 0..<totalFiles {
            try Task.checkCancellation()
            
            // Simulate file processing time
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            
            // Random file name and size
            let fileName = fakeFileNames.randomElement() ?? "FILE_\(String(format: "%03d", i)).RAF"
            let fileSize = Int64.random(in: 15_000_000...85_000_000) // 15-85 MB per file (realistic for video)
            
            // Occasionally simulate an error (1% chance)
            if Double.random(in: 0...1) < 0.01 {
                let error = NSError(domain: "FakeTransferError", code: 1001, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated transfer error for testing"
                ])
                onError(fileName, error)
            } else {
                onProgress(fileName, fileSize)
            }

            SharedLogger.debug("Fake progress: \(i+1)/\(totalFiles) - \(fileName)")
        }
    }
    
    @MainActor
    static func simulateFakeVerifyProgress(
        totalFiles: Int,
        sourceURL: URL,
        destURL: URL,
        onProgress: @escaping @MainActor (String) -> Void,
        onResult: @escaping @MainActor (ResultRow) -> Void
    ) async throws {
        
        // Verification is typically faster than copy, aim for 30 seconds
        let targetDurationSeconds: Double = 30.0 // 30 seconds for verification
        let filesPerSecond = Double(totalFiles) / targetDurationSeconds
        let interval = 1.0 / filesPerSecond

        SharedLogger.debug("Fake verification will take \(targetDurationSeconds)s for \(totalFiles) files (\(String(format: "%.2f", filesPerSecond)) files/sec)")
        
        let fakeFileNames = [
            "DSC00001.ARW", "DSC00002.ARW", "DSC00003.ARW", "DSC00004.ARW", "DSC00005.ARW",
            "C0001.MP4", "C0002.MP4", "C0003.MP4", "C0004.MP4", "C0005.MP4",
            "DSC00006.JPG", "DSC00007.JPG", "DSC00008.JPG", "DSC00009.JPG", "DSC00010.JPG",
            "A001_C001_230825_R4K8.MOV", "A001_C002_230825_R4K8.MOV", "A001_C003_230825_R4K8.MOV",
            "PROXY001.MP4", "PROXY002.MP4", "PROXY003.MP4",
            "AUDIO_CH1.WAV", "AUDIO_CH2.WAV", "SYNC_DATA.XML", "METADATA.XML"
        ]
        
        for i in 0..<totalFiles {
            try Task.checkCancellation()
            
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            
            let fileName = fakeFileNames.randomElement() ?? "FILE_\(String(format: "%03d", i)).RAF"
            onProgress(fileName)
            
            // 99% files match, 1% have issues for testing
            let statusText = Double.random(in: 0...1) < 0.99 ? "Match" : "Content Mismatch"
            let fileSize = Int64.random(in: 1000...50_000_000) // Random file size for testing
            let result = ResultRow(
                path: fileName,
                status: statusText,
                size: fileSize,
                checksum: statusText == "Match" ? "abc123def456" : nil,
                destination: nil
            )
            onResult(result)

            SharedLogger.debug("Fake verify: \(i+1)/\(totalFiles) - \(fileName) (\(statusText))")
        }
    }
}
