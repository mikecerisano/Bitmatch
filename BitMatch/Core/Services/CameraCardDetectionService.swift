// Core/Services/CameraCardDetectionService.swift - Automatic camera card detection
import Foundation
import Combine

#if os(macOS)
import AppKit
#endif

// MARK: - Camera Card Detection Service

@MainActor
final class CameraCardDetectionService: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var detectedCameraCards: [CameraCard] = []
    @Published private(set) var isMonitoring = false
    
    // MARK: - Private Properties
    private var volumeMonitor: VolumeMonitor?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupVolumeMonitoring()
    }
    
    deinit {
        // Clean up resources without modifying @Published properties
        // to avoid MainActor requirements in deinit
        volumeMonitor?.stopMonitoring()
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        volumeMonitor?.startMonitoring()

        // Initial scan of existing volumes
        scanExistingVolumes()

        SharedLogger.info("Camera card detection started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        volumeMonitor?.stopMonitoring()
        detectedCameraCards.removeAll()

        SharedLogger.info("Camera card detection stopped")
    }
    
    func rescanVolumes() {
        scanExistingVolumes()
    }
    
    // MARK: - Private Methods
    
    private func setupVolumeMonitoring() {
        volumeMonitor = VolumeMonitor { [weak self] event in
            // Since CameraCardDetectionService is @MainActor, schedule on main queue
            DispatchQueue.main.async {
                Task { @MainActor [weak self] in
                    await self?.handleVolumeEvent(event)
                }
            }
        }
    }
    
    private func scanExistingVolumes() {
        Task {
            // Future enhancement: implement periodic volume rescans if needed
            let volumes: [URL] = [] // await VolumeScanner.getAvailableVolumes()
            
            for volume in volumes {
                if let cameraCard = await detectCameraStructure(at: volume) {
                    await addDetectedCamera(cameraCard)
                }
            }
        }
    }
    
    private func handleVolumeEvent(_ event: VolumeEvent) async {
        switch event.type {
        case .mounted:
            SharedLogger.info("New volume mounted: \(event.volume.lastPathComponent)")
            
            // Small delay to allow volume to fully mount
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            if let cameraCard = await detectCameraStructure(at: event.volume) {
                await addDetectedCamera(cameraCard)
                await notifyUserOfDetection(cameraCard)
            }

        case .unmounted:
            SharedLogger.info("Volume unmounted: \(event.volume.lastPathComponent)")
            await removeDetectedCamera(at: event.volume)
        }
    }
    
    private func addDetectedCamera(_ cameraCard: CameraCard) async {
        // Avoid duplicates
        guard !detectedCameraCards.contains(where: { $0.volumeURL.path == cameraCard.volumeURL.path }) else {
            return
        }

        detectedCameraCards.append(cameraCard)
        SharedLogger.info("Camera card detected: \(cameraCard.cameraType.rawValue) at \(cameraCard.volumeURL.lastPathComponent)")
    }
    
    private func removeDetectedCamera(at volume: URL) async {
        detectedCameraCards.removeAll { $0.volumeURL.path == volume.path }
        SharedLogger.info("Camera card removed: \(volume.lastPathComponent)")
    }
    
    private func notifyUserOfDetection(_ cameraCard: CameraCard) async {
        // Post notification for UI to handle
        NotificationCenter.default.post(
            name: .cameraCardDetected,
            object: nil,
            userInfo: ["cameraCard": cameraCard]
        )
        
        // Optional: Show system notification
        // Note: System notification preferences will be handled by the UI layer (AppCoordinator)
        // This keeps the service decoupled from UI preferences
    }
    
    private func detectCameraStructure(at volume: URL) async -> CameraCard? {
        return await CameraStructureDetector.detectCameraType(at: volume)
    }
}


// MARK: - Volume Monitor

class VolumeMonitor {
    private let eventHandler: (VolumeEvent) -> Void
    private var isActive = false
    
    init(eventHandler: @escaping (VolumeEvent) -> Void) {
        self.eventHandler = eventHandler
    }
    
    func startMonitoring() {
        guard !isActive else { return }
        
        isActive = true
        
        #if os(macOS)
        // Monitor volume mount/unmount events using NSWorkspace
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let volumeURL = notification.userInfo?["NSDevicePath"] as? String {
                let event = VolumeEvent(
                    type: .mounted,
                    volume: URL(fileURLWithPath: volumeURL),
                    timestamp: Date()
                )
                self?.eventHandler(event)
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let volumeURL = notification.userInfo?["NSDevicePath"] as? String {
                let event = VolumeEvent(
                    type: .unmounted,
                    volume: URL(fileURLWithPath: volumeURL),
                    timestamp: Date()
                )
                self?.eventHandler(event)
            }
        }
        #endif
    }
    
    func stopMonitoring() {
        guard isActive else { return }
        
        isActive = false
        #if os(macOS)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        #endif
    }
    
    deinit {
        stopMonitoring()
    }
}
