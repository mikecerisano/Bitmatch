// Core/ViewModels/CameraLabelViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class CameraLabelViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var destinationLabelSettings = CameraLabelSettings()
    @Published var detectedCamera: CameraType = .generic
    @Published var currentFingerprint: CameraMemoryService.CameraFingerprint?
    
    // MARK: - Private Properties
    /// Owned detection task and its generation: reselecting the source
    /// cancels the in-flight detection and only the latest may publish.
    private var detectionTask: Task<Void, Never>?
    private var detectionGeneration = 0
    
    // MARK: - Initialization
    init() {
        loadCameraLabelSettings()
    }
    
    // MARK: - Public Methods (Updated with Memory System)
    func detectCameraWithMemory(at url: URL) {
        // Supersede any in-flight detection: only the latest source may
        // publish. Detection itself honors task cancellation at the
        // orchestrator's stage boundaries.
        detectionTask?.cancel()
        detectionGeneration += 1
        let generation = detectionGeneration
        detectionTask = Task.detached {
            // Filesystem enumeration, metadata subprocesses, and
            // fingerprinting run off the main actor.
            let detectedName = CameraDetectionOrchestrator.shared.detectCamera(at: url)
            let cameraType = Self.mapCameraNameToType(detectedName)
            // A superseded request must not start further scans.
            guard !Task.isCancelled else { return }

            // Then try to get the camera's fingerprint
            let fingerprint = CameraMemoryService.shared.getCameraFingerprint(at: url)
            guard !Task.isCancelled else { return }
            // Folder-analysis naming suggestion, also off the main actor.
            let suggestion = CameraNamingService.getBestCameraSuggestion(for: url)

            await MainActor.run { [weak self] in
                guard let self, generation == self.detectionGeneration else { return }
                self.detectedCamera = cameraType
                self.currentFingerprint = fingerprint

                // Check if we remember this specific camera
                if let fingerprint = fingerprint,
                   let rememberedLabel = CameraMemoryService.shared.getRememberedLabel(for: fingerprint) {

                    // We've seen this exact camera before! Use its remembered label
                    self.destinationLabelSettings.label = rememberedLabel

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.saveCameraLabelSettings()
                    }

                    SharedLogger.info("Recognized camera: \(fingerprint.displayName) → Auto-applied label: \"\(rememberedLabel)\"", category: .transfer)

                } else if self.destinationLabelSettings.label.isEmpty {
                    // Try intelligent camera naming from video files first
                    if let cameraSuggestion = suggestion {
                        self.destinationLabelSettings.label = cameraSuggestion.suggestedName

                        SharedLogger.info("Auto-detected camera designation: \(cameraSuggestion.cameraDesignation) from \(cameraSuggestion.sourceFilename)", category: .transfer)
                        SharedLogger.debug("Suggested folder name: \"\(cameraSuggestion.suggestedName)\" (confidence: \(cameraSuggestion.confidence * 100)%)", category: .transfer)

                    } else if cameraType != .generic {
                        // Fallback to model-based naming using clean camera names
                        if let detectedName = detectedName {
                            let cleanName = CleanCameraNameService.shared.getCleanCameraName(from: detectedName)
                            self.destinationLabelSettings.label = cleanName
                        } else {
                            let suggestedLabel = self.getCameraModelLabel(for: cameraType)
                            self.destinationLabelSettings.label = suggestedLabel
                        }
                    }

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.saveCameraLabelSettings()
                    }

                    SharedLogger.info("New camera detected: \(cameraType.rawValue)", category: .transfer)
                }
            }
        }
    }
    
    // Call this when user changes the label
    func onLabelChanged() {
        // Store the fingerprint with the current label for future use
        if let fingerprint = currentFingerprint, !destinationLabelSettings.label.isEmpty {
            CameraMemoryService.shared.updateLabel(destinationLabelSettings.label, for: fingerprint)
        }
        saveCameraLabelSettings()
    }
    
    func generateDestinationPath(source: URL, destination: URL) -> URL {
        let baseName = source.lastPathComponent
        let labeledName: String
        if destinationLabelSettings.generateUniqueName {
            labeledName = generateUniqueFilename(base: baseName, at: destination)
        } else {
            labeledName = baseName
        }
        return destination.appendingPathComponent(labeledName)
    }
    
    private func generateUniqueFilename(base: String, at destination: URL) -> String {
        // Future enhancement: implement unique filename generation to avoid collisions
        return base
    }
    
    func saveSettings() {
        saveCameraLabelSettings()
        // Also update memory if we have a fingerprint
        if let fingerprint = currentFingerprint, !destinationLabelSettings.label.isEmpty {
            CameraMemoryService.shared.updateLabel(destinationLabelSettings.label, for: fingerprint)
        }
    }
    
    func clearCameraLabel() {
        destinationLabelSettings.label = ""
        detectedCamera = .generic
        currentFingerprint = nil
        saveCameraLabelSettings()
        SharedLogger.debug("Cleared camera label - no source selected", category: .transfer)
    }
    
    // MARK: - Camera Label Generation (Model-based, not position)
    private func getCameraModelLabel(for camera: CameraType) -> String {
        switch camera {
        case .sony: return "SONY"
        case .sonyFX6: return "FX6"
        case .sonyFX3: return "FX3"
        case .sonyA7S: return "A7S"
        case .canon: return "CANON"
        case .canonC70: return "C70"
        case .arri: return "ARRI"
        case .arriAlexa: return "ALEXA"
        case .arriAmira: return "AMIRA"
        case .red: return "RED"
        case .redCamera: return "RED"
        case .redDragon: return "RED"
        case .blackmagic: return "BMPCC"
        case .blackmagicPocket: return "BMPCC"
        case .panasonic: return "PANASONIC"
        case .fujifilm: return "FUJIFILM"
        case .nikon: return "NIKON"
        case .gopro: return "GOPRO"
        case .dji: return "DJI"
        case .insta360: return "INSTA360"
        case .genericDCIM: return "DCIM"
        case .genericMedia: return "MEDIA"
        case .generic: return ""
        }
    }
    
    // MARK: - Settings Persistence
    private func loadCameraLabelSettings() {
        if let data = UserDefaults.standard.data(forKey: "destLabelSettings"),
           let settings = try? JSONDecoder().decode(CameraLabelSettings.self, from: data) {
            destinationLabelSettings = settings
        }
    }
    
    private func saveCameraLabelSettings() {
        do {
            let data = try JSONEncoder().encode(destinationLabelSettings)
            UserDefaults.standard.set(data, forKey: "destLabelSettings")
        } catch {
            SharedLogger.error("Failed to save camera label settings: \(error)", category: .transfer)
        }
    }
    
    // MARK: - Camera Type Mapping
    private nonisolated static func mapCameraNameToType(_ name: String?) -> CameraType {
        guard let name = name else { return .generic }
        
        let lowercased = name.lowercased()
        
        if lowercased.contains("arri") {
            if lowercased.contains("alexa") { return .arriAlexa }
            if lowercased.contains("amira") { return .arriAmira }
        }
        if lowercased.contains("red") && lowercased.contains("dragon") { return .redDragon }
        if lowercased.contains("sony") {
            if lowercased.contains("fx6") { return .sonyFX6 }
            if lowercased.contains("fx3") { return .sonyFX3 }
            if lowercased.contains("a7s") { return .sonyA7S }
        }
        if lowercased.contains("canon") && lowercased.contains("c70") { return .canonC70 }
        if lowercased.contains("blackmagic") && lowercased.contains("pocket") { return .blackmagicPocket }
        if lowercased.contains("dji") { return .dji }
        if lowercased.contains("gopro") { return .gopro }
        
        return .generic
    }
    
    // MARK: - Metadata Generation
    func generateTransferMetadata(
        jobID: UUID,
        jobStart: Date,
        sourceURL: URL?,
        destinationPath: String,
        sourceFolderInfo: FolderInfo?,
        prefs: ReportPrefs,
        verificationMode: VerificationMode,
        matchCount: Int,
        workers: Int,
        totalBytesProcessed: Int64
    ) -> TransferMetadata {
        // Create TransferMetadata using the actual SharedModels structure
        return TransferMetadata(
            sourceURL: sourceURL ?? URL(fileURLWithPath: "/"),
            destinationURLs: [URL(fileURLWithPath: destinationPath)],
            startTime: jobStart,
            endTime: Date(), // Current time as end time
            totalFiles: matchCount,
            totalSize: totalBytesProcessed,
            verificationMode: verificationMode,
            cameraSettings: destinationLabelSettings
        )
    }
}
