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
    private let cameraDetection = CameraDetectionOrchestrator.shared
    
    // MARK: - Initialization
    init() {
        loadCameraLabelSettings()
    }
    
    // MARK: - Public Methods (Updated with Memory System)
    func detectCameraWithMemory(at url: URL) {
        Task {
            // First detect the camera model (existing functionality)
            let detectedName = cameraDetection.detectCamera(at: url)
            let cameraType = mapCameraNameToType(detectedName)
            
            // Then try to get the camera's fingerprint
            let fingerprint = CameraMemoryService.shared.getCameraFingerprint(at: url)
            
            await MainActor.run {
                self.detectedCamera = cameraType
                self.currentFingerprint = fingerprint
                
                // Check if we remember this specific camera
                if let fingerprint = fingerprint,
                   let rememberedLabel = CameraMemoryService.shared.getRememberedLabel(for: fingerprint) {
                    
                    // We've seen this exact camera before! Use its remembered label
                    destinationLabelSettings.label = rememberedLabel
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        saveCameraLabelSettings()
                    }
                    
                    print("📷 Recognized camera: \(fingerprint.displayName) → Auto-applied label: \"\(rememberedLabel)\"")
                    
                } else if destinationLabelSettings.label.isEmpty {
                    // Try intelligent camera naming from video files first
                    if let cameraSuggestion = CameraNamingService.getBestCameraSuggestion(for: url) {
                        destinationLabelSettings.label = cameraSuggestion.suggestedName
                        
                        print("🎬 Auto-detected camera designation: \(cameraSuggestion.cameraDesignation) from \(cameraSuggestion.sourceFilename)")
                        print("📝 Suggested folder name: \"\(cameraSuggestion.suggestedName)\" (confidence: \(cameraSuggestion.confidence * 100)%)")
                        
                    } else if cameraType != .generic {
                        // Fallback to model-based naming using clean camera names
                        if let detectedName = detectedName {
                            let cleanName = CleanCameraNameService.shared.getCleanCameraName(from: detectedName)
                            destinationLabelSettings.label = cleanName
                        } else {
                            let suggestedLabel = getCameraModelLabel(for: cameraType)
                            destinationLabelSettings.label = suggestedLabel
                        }
                    }
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        saveCameraLabelSettings()
                    }
                    
                    print("📷 New camera detected: \(cameraType.rawValue)")
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
        let labeledName = destinationLabelSettings.generateUniqueName(
            base: baseName,
            at: destination
        )
        return destination.appendingPathComponent(labeledName)
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
        print("🧹 Cleared camera label - no source selected")
    }
    
    // MARK: - Camera Label Generation (Model-based, not position)
    private func getCameraModelLabel(for camera: CameraType) -> String {
        switch camera {
        case .arriAlexa: return "ALEXA"
        case .arriAmira: return "AMIRA"
        case .redDragon: return "RED"
        case .sonyFX6: return "FX6"
        case .sonyFX3: return "FX3"
        case .sonyA7S: return "A7S"
        case .canonC70: return "C70"
        case .blackmagicPocket: return "BMPCC"
        case .dji: return "DJI"  // Don't assume drone
        case .gopro: return "GOPRO"
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
            print("Failed to save camera label settings: \(error)")
        }
    }
    
    // MARK: - Camera Type Mapping
    private func mapCameraNameToType(_ name: String?) -> CameraType {
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
        return TransferMetadata.forCopyOperation(
            jobId: jobID,
            jobStart: jobStart,
            sourceURL: sourceURL,
            destinationPath: destinationPath,
            sourceFolderInfo: sourceFolderInfo,
            cameraLabel: destinationLabelSettings,
            detectedCamera: detectedCamera,
            prefs: prefs,
            verificationMode: verificationMode,
            matchCount: matchCount,
            workers: workers,
            totalBytesProcessed: totalBytesProcessed
        )
    }
}
