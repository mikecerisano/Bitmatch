// OperationStateService.swift - Manages pause/resume state and persistence
import Foundation
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
class OperationStateService: ObservableObject {
    
    // MARK: - Published State
    @Published var currentState: OperationState = .idle
    @Published var pauseResumeCapabilities = PauseResumeCapabilities()
    @Published var savedOperations: [SavedOperationState] = []
    
    // MARK: - Private State
    private var currentOperationId: UUID?
    private var currentSourceURL: URL?
    private var currentDestinationURLs: [URL] = []
    private var currentVerificationMode: String?
    private var currentMode: String?
    private var startTime: Date?
    private var pausedOperationData: SavedOperationState?
    private let userDefaults = UserDefaults.standard
    private let savedOperationsKey = "BitMatch_SavedOperations"
    
    // MARK: - Initialization
    
    init() {
        loadSavedOperations()
        setupSystemNotifications()
    }
    
    // MARK: - Operation Lifecycle
    
    func startOperation(id: UUID, sourceURL: URL, destinationURLs: [URL], totalFiles: Int, totalBytes: Int64, verificationMode: String? = nil, mode: String? = nil) {
        currentOperationId = id
        currentState = .inProgress
        currentSourceURL = sourceURL
        currentDestinationURLs = destinationURLs
        currentVerificationMode = verificationMode
        currentMode = mode
        startTime = Date()
        
        // Clear any existing paused state for fresh operations
        if let existingIndex = savedOperations.firstIndex(where: { $0.operationId == id }) {
            savedOperations.remove(at: existingIndex)
            saveToDisk()
        }

        SharedLogger.info("StateService: started operation id=\(id)", category: .transfer)
    }
    
    func pauseOperation(reason: PauseInfo.PauseReason, currentProgress: OperationProgress?) {
        guard let operationId = currentOperationId,
              currentState.canPause else { return }
        
        let pauseInfo = PauseInfo(
            pausedAt: Date(),
            currentFile: currentProgress?.currentFile,
            filesProcessed: currentProgress?.filesProcessed ?? 0,
            totalFiles: currentProgress?.totalFiles ?? 0,
            bytesProcessed: currentProgress?.bytesProcessed ?? 0,
            reason: reason
        )
        
        currentState = .paused(pauseInfo)
        
        // Save operation state for persistence
        if let progress = currentProgress {
            let savedState = SavedOperationState(
                operationId: operationId,
                pausedAt: Date(),
                pauseInfo: pauseInfo,
                progress: progress,
                reason: reason,
                sourceURL: currentSourceURL,
                destinationURLs: currentDestinationURLs,
                verificationMode: currentVerificationMode,
                startTime: startTime
            )
            
            // Update or add saved state
            if let existingIndex = savedOperations.firstIndex(where: { $0.operationId == operationId }) {
                savedOperations[existingIndex] = savedState
            } else {
                savedOperations.append(savedState)
            }
            
            saveToDisk()
        }

        SharedLogger.info("StateService: paused (reason=\(reason))", category: .transfer)
    }
    
    func resumeOperation() -> Bool {
        guard currentState.canResume,
              let operationId = currentOperationId else { return false }
        
        currentState = .resuming
        
        // Remove from saved operations since we're resuming
        if let savedIndex = savedOperations.firstIndex(where: { $0.operationId == operationId }) {
            savedOperations.remove(at: savedIndex)
            saveToDisk()
        }
        
        // Transition to active state after brief resuming state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.currentState == .resuming {
                self.currentState = .inProgress
            }
        }
        
        SharedLogger.info("StateService: resumed", category: .transfer)
        return true
    }
    
    func completeOperation() {
        guard let operationId = currentOperationId else { return }
        
        // Clean up any saved state
        if let savedIndex = savedOperations.firstIndex(where: { $0.operationId == operationId }) {
            savedOperations.remove(at: savedIndex)
            saveToDisk()
        }
        
        currentOperationId = nil
        SharedLogger.info("StateService: completed and cleaned up", category: .transfer)
    }
    
    func cancelOperation() {
        guard let operationId = currentOperationId else { return }
        
        currentState = .cancelled
        
        // Clean up saved state
        if let savedIndex = savedOperations.firstIndex(where: { $0.operationId == operationId }) {
            savedOperations.remove(at: savedIndex)
            saveToDisk()
        }
        
        currentOperationId = nil
        SharedLogger.warning("StateService: cancelled and cleaned up", category: .transfer)
    }
    
    // MARK: - Saved Operations Management
    
    func getSavedOperation(id: UUID) -> SavedOperationState? {
        return savedOperations.first { $0.operationId == id }
    }
    
    func deleteSavedOperation(id: UUID) {
        if let index = savedOperations.firstIndex(where: { $0.operationId == id }) {
            savedOperations.remove(at: index)
            saveToDisk()
        }
    }
    
    func restoreFromSavedOperation(_ savedState: SavedOperationState) {
        currentOperationId = savedState.operationId
        currentState = .paused(savedState.pauseInfo)
        pausedOperationData = savedState
        
        SharedLogger.info("StateService: restored from saved state", category: .transfer)
    }
    
    // MARK: - System Integration
    
    private func setupSystemNotifications() {
        #if canImport(UIKit)
        // iOS background/foreground notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // Battery level monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        #endif
        
        #if canImport(AppKit)
        // macOS sleep/wake notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        #endif
    }
    
    // MARK: - System Event Handlers
    
    #if canImport(UIKit)
    @objc private func appDidEnterBackground() {
        if currentState.canPause {
            pauseOperation(reason: .backgrounded, currentProgress: nil)
        }
    }
    
    @objc private func appWillEnterForeground() {
        // Could automatically resume or prompt user
        if currentState.isPaused {
            SharedLogger.info("StateService: app foreground with paused operation", category: .transfer)
        }
    }
    
    @objc private func batteryLevelChanged() {
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0.15 && batteryLevel > 0 && currentState.canPause {
            pauseOperation(reason: .lowBattery, currentProgress: nil)
            SharedLogger.warning("StateService: auto-paused (battery=\(Int(batteryLevel * 100))%)", category: .transfer)
        }
    }
    #endif
    
    #if canImport(AppKit)
    @objc private func systemWillSleep() {
        if currentState.canPause {
            pauseOperation(reason: .systemSleep, currentProgress: nil)
        }
    }
    
    @objc private func systemDidWake() {
        if currentState.isPaused {
            SharedLogger.info("StateService: system wake with paused operation", category: .transfer)
        }
    }
    #endif
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(savedOperations)
            userDefaults.set(data, forKey: savedOperationsKey)
            SharedLogger.debug("StateService: saved \(savedOperations.count) operations", category: .transfer)
        } catch {
            SharedLogger.error("StateService: failed to save operations: \(error)", category: .transfer)
        }
    }
    
    private func loadSavedOperations() {
        guard let data = userDefaults.data(forKey: savedOperationsKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            savedOperations = try decoder.decode([SavedOperationState].self, from: data)
            SharedLogger.debug("StateService: loaded \(savedOperations.count) saved operations", category: .transfer)
        } catch {
            SharedLogger.error("StateService: failed to load saved operations: \(error)", category: .transfer)
        }
    }
    
    // MARK: - Utilities
    
    func updateCapabilities(canPause: Bool, canResume: Bool, estimatedPauseTime: TimeInterval? = nil) {
        pauseResumeCapabilities = PauseResumeCapabilities(
            canPause: canPause,
            canResume: canResume,
            estimatedPauseTime: estimatedPauseTime,
            supportsPersistence: true
        )
    }
    
    func getResumeRecommendation() -> ResumeRecommendation? {
        guard currentState.isPaused else { return nil }
        
        #if os(iOS)
        let batteryLevel = UIDevice.current.batteryLevel
        let isCharging = UIDevice.current.batteryState == .charging
        
        if batteryLevel < 0.20 && !isCharging {
            return ResumeRecommendation(
                shouldResume: false,
                reason: "Low battery (\(Int(batteryLevel * 100))%) - Consider charging before resuming",
                priority: .high
            )
        }
        #endif
        
        return ResumeRecommendation(
            shouldResume: true,
            reason: "Ready to resume",
            priority: .normal
        )
    }

    // MARK: - Checkpoint Updates (for crash/interruption resume)
    func updateCheckpoint(operationId: UUID, filesProcessed: Int, totalFiles: Int, lastFile: String?) {
        let progress = OperationProgress(
            overallProgress: totalFiles > 0 ? Double(filesProcessed) / Double(totalFiles) : 0,
            currentFile: lastFile,
            filesProcessed: filesProcessed,
            totalFiles: totalFiles,
            currentStage: .copying,
            speed: nil,
            timeRemaining: nil,
            elapsedTime: nil,
            averageSpeed: nil,
            peakSpeed: nil,
            bytesProcessed: nil,
            totalBytes: nil,
            stageProgress: nil,
            reusedCopies: nil
        )
        let savedState = SavedOperationState(
            operationId: operationId,
            pausedAt: Date(),
            pauseInfo: PauseInfo(
                pausedAt: Date(),
                currentFile: lastFile,
                filesProcessed: filesProcessed,
                totalFiles: totalFiles,
                bytesProcessed: 0,
                reason: .error
            ),
            progress: progress,
            reason: .error,
            sourceURL: currentSourceURL,
            destinationURLs: currentDestinationURLs,
            verificationMode: currentVerificationMode,
            startTime: startTime
        )
        if let existingIndex = savedOperations.firstIndex(where: { $0.operationId == operationId }) {
            savedOperations[existingIndex] = savedState
        } else {
            savedOperations.append(savedState)
        }
        saveToDisk()
    }
}

// MARK: - Supporting Types

struct SavedOperationState: Codable, Identifiable {
    var id: UUID = UUID()
    let operationId: UUID
    let pausedAt: Date
    let pauseInfo: PauseInfo
    let progress: OperationProgress
    let reason: PauseInfo.PauseReason
    let sourceURL: URL?
    let destinationURLs: [URL]?
    let verificationMode: String?
    let startTime: Date?
    
    var formattedPauseTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: pausedAt)
    }
    
    var timeSincePaused: TimeInterval {
        Date().timeIntervalSince(pausedAt)
    }
    
    var canAutoResume: Bool {
        // Auto-resume if paused for system reasons and it's been reasonable time
        switch reason {
        case .systemSleep, .backgrounded:
            return timeSincePaused < 3600 // 1 hour
        case .lowBattery:
            #if os(iOS)
            return UIDevice.current.batteryLevel > 0.3
            #else
            return true
            #endif
        case .userRequested, .error:
            return false
        }
    }
}

struct PauseResumeCapabilities {
    let canPause: Bool
    let canResume: Bool
    let estimatedPauseTime: TimeInterval?
    let supportsPersistence: Bool
    
    init(canPause: Bool = false, canResume: Bool = false, estimatedPauseTime: TimeInterval? = nil, supportsPersistence: Bool = false) {
        self.canPause = canPause
        self.canResume = canResume
        self.estimatedPauseTime = estimatedPauseTime
        self.supportsPersistence = supportsPersistence
    }
}

struct ResumeRecommendation {
    let shouldResume: Bool
    let reason: String
    let priority: Priority
    
    enum Priority {
        case low, normal, high
    }
}

// MARK: - Codable conformance for PauseInfo is declared in OperationModels.swift
