// Core/Services/VolumeMonitorService.swift
import Foundation
import Combine

#if os(macOS)
import DiskArbitration
#endif

final class VolumeMonitorService: ObservableObject {
    static let shared = VolumeMonitorService()
    
    // Published properties for UI updates
    @Published var availableCameraCards: [DetectedVolume] = []
    @Published var availableBackupDrives: [DetectedVolume] = []
    
    // Monitoring state
    #if os(macOS)
    private var diskArbitrationSession: DASession?
    #endif
    private let detectionQueue = DispatchQueue(label: "volume.detection", qos: .utility)
    
    // File system monitoring
    #if os(macOS)
    private var volumesDispatchSource: DispatchSourceFileSystemObject?
    #endif
    
    struct DetectedVolume: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        let capacity: Int64
        let available: Int64
        let type: VolumeType
        let cameraInfo: String?
        let devicePath: String
        
        enum VolumeType {
            case cameraCard
            case backupDrive
        }
        
        var displayName: String {
            if let camera = cameraInfo {
                return "\(name) (\(camera))"
            }
            return name
        }
        
        var capacityFormatted: String {
            ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
        }
    }
    
    private init() {
        startMonitoring()
        // Initial scan of existing volumes
        scanExistingVolumes()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Volume Monitoring
    
    private func startMonitoring() {
        #if os(macOS)
        startDiskArbitrationMonitoring()
        startFileSystemMonitoring()
        #endif
        print("📱 Volume monitoring started")
    }
    
    #if os(macOS)
    private func startDiskArbitrationMonitoring() {
        diskArbitrationSession = DASessionCreate(kCFAllocatorDefault)
        guard let session = diskArbitrationSession else {
            print("❌ Failed to create DiskArbitration session")
            return
        }
        
        // Set up callbacks for disk appeared/disappeared
        let appearCallback: DADiskAppearedCallback = { disk, context in
            guard let service = Unmanaged<VolumeMonitorService>.fromOpaque(context!).takeUnretainedValue() as VolumeMonitorService? else { return }
            service.handleDiskAppeared(disk)
        }
        
        let disappearCallback: DADiskDisappearedCallback = { disk, context in
            guard let service = Unmanaged<VolumeMonitorService>.fromOpaque(context!).takeUnretainedValue() as VolumeMonitorService? else { return }
            service.handleDiskDisappeared(disk)
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        DARegisterDiskAppearedCallback(session, nil, appearCallback, context)
        DARegisterDiskDisappearedCallback(session, nil, disappearCallback, context)
        
        DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        print("📱 DiskArbitration monitoring started")
    }
    
    private func startFileSystemMonitoring() {
        let volumesPath = "/Volumes"
        let fileDescriptor = open(volumesPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("❌ Failed to open /Volumes for monitoring")
            return
        }
        
        volumesDispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: detectionQueue
        )
        
        volumesDispatchSource?.setEventHandler { [weak self] in
            print("📁 /Volumes directory changed - checking for volume changes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Small delay to let mounting/unmounting complete
                self?.checkForVolumeChanges()
            }
        }
        
        volumesDispatchSource?.setCancelHandler {
            close(fileDescriptor)
        }
        
        volumesDispatchSource?.resume()
        print("📱 File system monitoring started")
    }
    #endif
    
    private func stopMonitoring() {
        #if os(macOS)
        if let session = diskArbitrationSession {
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            diskArbitrationSession = nil
        }
        
        volumesDispatchSource?.cancel()
        volumesDispatchSource = nil
        #endif
        
        print("📱 Volume monitoring stopped")
    }
    
    // MARK: - Disk Callbacks
    
    #if os(macOS)
    private func handleDiskAppeared(_ disk: DADisk) {
        detectionQueue.async { [weak self] in
            self?.processDiskAppeared(disk)
        }
    }
    
    private func handleDiskDisappeared(_ disk: DADisk) {
        detectionQueue.async { [weak self] in
            self?.processDiskDisappeared(disk)
        }
    }
    #endif
    
    #if os(macOS)
    private func processDiskAppeared(_ disk: DADisk) {
        guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
            print("❌ No description for disk")
            return
        }
        
        // Log all disk information for debugging
        print("🔍 Disk appeared with description:")
        for (key, value) in description {
            print("   \(key): \(value)")
        }
        
        // Only process mountable volumes
        let isMountable = description[kDADiskDescriptionVolumeMountableKey as String] as? Bool ?? false
        guard isMountable else {
            print("⏭️ Skipping non-mountable disk")
            return
        }
        
        let volumeName = description[kDADiskDescriptionVolumeNameKey as String] as? String ?? "Unknown"
        print("🔍 Mountable disk appeared: \(volumeName)")
        
        // For mountable volumes, try to mount them first if not already mounted
        if let volumePath = description[kDADiskDescriptionVolumePathKey as String] as? URL {
            print("📂 Volume already mounted at: \(volumePath)")
            analyzeAndAddVolume(at: volumePath, description: description)
        } else {
            print("🔄 Volume not mounted, attempting to mount...")
            // Try to mount the disk
            DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionDefault), { disk, dissenter, context in
                // This callback runs when mount completes
                if let dissenter = dissenter {
                    print("❌ Failed to mount disk: \(DADissenterGetStatus(dissenter))")
                } else {
                    print("✅ Disk mounted successfully")
                    // Re-check for volume path after mounting
                    if let newDescription = DADiskCopyDescription(disk) as? [String: Any],
                       let volumePath = newDescription[kDADiskDescriptionVolumePathKey as String] as? URL {
                        DispatchQueue.global().async {
                            if let service = context.map({ Unmanaged<VolumeMonitorService>.fromOpaque($0).takeUnretainedValue() }) {
                                service.analyzeAndAddVolume(at: volumePath, description: newDescription)
                            }
                        }
                    }
                }
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }
    
    private func analyzeAndAddVolume(at volumePath: URL, description: [String: Any]) {
        // Skip system volumes and hidden volumes
        if isSystemVolume(description) {
            print("⏭️ Skipping system volume: \(volumePath)")
            return
        }
        
        // Analyze the volume
        print("🔬 Analyzing volume at: \(volumePath)")
        #if os(macOS)
        if let detectedVolume = analyzeVolume(at: volumePath, description: description) {
            print("✅ Volume detected as \(detectedVolume.type): \(detectedVolume.displayName)")
            DispatchQueue.main.async { [weak self] in
                self?.addDetectedVolume(detectedVolume)
            }
        } else {
            print("❌ Volume not recognized as camera card or backup drive")
        }
        #else
        // Volume analysis not available on iOS
        print("⚠️ Volume analysis not available on iOS")
        #endif
    }
    #endif
    
    #if os(macOS)
    private func processDiskDisappeared(_ disk: DADisk) {
        guard let description = DADiskCopyDescription(disk) as? [String: Any],
              let devicePath = description[kDADiskDescriptionDevicePathKey as String] as? String else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.removeDetectedVolume(devicePath: devicePath)
        }
    }
    #endif
    
    // MARK: - Volume Analysis
    
    private func checkForVolumeChanges() {
        print("🔍 Checking for volume changes...")
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            guard let currentVolumes = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
                                                                           includingPropertiesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey],
                                                                           options: [.skipsHiddenFiles]) else {
                print("❌ Could not scan /Volumes directory")
                return
            }
            
            let currentVolumePaths = Set(currentVolumes.map { $0.path })
            
            // Check for removed volumes
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Remove camera cards that no longer exist
                let removedCameraCards = self.availableCameraCards.filter { card in
                    !currentVolumePaths.contains(card.url.path)
                }
                
                for card in removedCameraCards {
                    print("📤 Camera card removed: \(card.displayName)")
                    self.availableCameraCards.removeAll { $0.id == card.id }
                }
                
                // Remove backup drives that no longer exist
                let removedBackupDrives = self.availableBackupDrives.filter { drive in
                    !currentVolumePaths.contains(drive.url.path)
                }
                
                for drive in removedBackupDrives {
                    print("📤 Backup drive removed: \(drive.displayName)")
                    self.availableBackupDrives.removeAll { $0.id == drive.id }
                }
            }
            
            // Check for new volumes
            for volumeURL in currentVolumes {
                let volumePath = volumeURL.path
                
                // Skip if we already have this volume
                let alreadyDetected = DispatchQueue.main.sync {
                    self.availableCameraCards.contains { $0.url.path == volumePath } ||
                    self.availableBackupDrives.contains { $0.url.path == volumePath }
                }
                
                if !alreadyDetected {
                    print("🔍 New volume detected: \(volumeURL.lastPathComponent)")
                    #if os(macOS)
                    if let detectedVolume = self.analyzeVolume(at: volumeURL, description: nil) {
                        DispatchQueue.main.async { [weak self] in
                            self?.addDetectedVolume(detectedVolume)
                        }
                    }
                    #else
                    // On iOS, volume analysis is not available
                    print("⚠️ Volume analysis not available on iOS")
                    #endif
                }
            }
            
            print("✅ Volume change check complete")
        }
    }
    
    private func scanExistingVolumes() {
        print("🔍 Scanning existing volumes...")
        detectionQueue.async { [weak self] in
            let fileManager = FileManager.default
            guard let volumes = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
                                                                    includingPropertiesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey],
                                                                    options: [.skipsHiddenFiles]) else {
                print("❌ Could not scan /Volumes directory")
                return
            }
            
            print("📂 Found \(volumes.count) volumes: \(volumes.map { $0.lastPathComponent })")
            
            for volumeURL in volumes {
                print("🔍 Scanning volume: \(volumeURL.lastPathComponent)")
                #if os(macOS)
                if let detectedVolume = self?.analyzeVolume(at: volumeURL, description: nil) {
                    DispatchQueue.main.async { [weak self] in
                        self?.addDetectedVolume(detectedVolume)
                    }
                }
                #else
                // Volume analysis not available on iOS
                print("⚠️ Volume analysis not available on iOS")
                #endif
            }
            
            print("✅ Volume scan complete")
        }
    }
    
    #if os(macOS)
    private func analyzeVolume(at url: URL, description: [String: Any]?) -> DetectedVolume? {
        let fileManager = FileManager.default
        
        print("🔍 Analyzing volume: \(url.path)")
        
        // Skip iOS simulators and development volumes first
        if isDevelopmentOrSimulatorVolume(url, description: description) {
            print("⏭️ Skipping development/simulator volume: \(url.lastPathComponent)")
            return nil
        }
        
        // Skip if not accessible - but try to get permission first
        if !fileManager.isReadableFile(atPath: url.path) {
            print("❌ Volume not readable: \(url.path) - trying to request access...")
            
            // Try to request access by checking if it starts accessing
            let startedAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if !fileManager.isReadableFile(atPath: url.path) {
                print("❌ Volume still not readable after requesting access")
                return nil
            } else {
                print("✅ Got access to volume after security request")
            }
        }
        
        print("✅ Volume is readable")
        
        // Get volume information
        guard let resourceValues = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsLocalKey
        ]) else { 
            print("❌ Could not get volume resource values")
            return nil 
        }
        
        let capacity = Int64(resourceValues.volumeTotalCapacity ?? 0)
        let available = Int64(resourceValues.volumeAvailableCapacity ?? 0)
        let isRemovable = resourceValues.volumeIsRemovable ?? false
        let isLocal = resourceValues.volumeIsLocal ?? true
        
        print("📊 Volume info: capacity=\(capacity), removable=\(isRemovable), local=\(isLocal)")
        
        let devicePath = description?[kDADiskDescriptionDevicePathKey as String] as? String ?? url.path
        let name = url.lastPathComponent
        
        // Determine volume type and camera info
        print("📷 Checking for camera...")
        if let cameraInfo = detectCameraVolume(at: url) {
            print("✅ Camera detected: \(cameraInfo)")
            // Camera card detected
            return DetectedVolume(
                url: url,
                name: name,
                capacity: capacity,
                available: available,
                type: .cameraCard,
                cameraInfo: cameraInfo,
                devicePath: devicePath
            )
        } else {
            print("❌ No camera detected")
        }
        
        print("💾 Checking if backup drive...")
        if isBackupDrive(capacity: capacity, isRemovable: isRemovable, isLocal: isLocal, url: url) {
            print("✅ Backup drive detected")
            // Large external drive suitable for backup
            return DetectedVolume(
                url: url,
                name: name,
                capacity: capacity,
                available: available,
                type: .backupDrive,
                cameraInfo: nil,
                devicePath: devicePath
            )
        } else {
            print("❌ Not a backup drive")
        }
        
        print("❌ Volume not recognized")
        return nil
    }
    #endif
    
    private func detectCameraVolume(at url: URL) -> String? {
        // Use existing camera detection service
        return CameraDetectionOrchestrator.shared.detectCamera(at: url)
    }
    
    private func isBackupDrive(capacity: Int64, isRemovable: Bool, isLocal: Bool, url: URL) -> Bool {
        // Criteria for backup drive:
        // 1. Over 500GB capacity
        // 2. Not the system drive
        // 3. Writable
        // 4. Local (not network)
        
        let minBackupCapacity: Int64 = 500 * 1024 * 1024 * 1024 // 500GB
        let capacityGB = capacity / (1024 * 1024 * 1024)
        
        print("💾 Backup drive check:")
        print("   Capacity: \(capacityGB)GB (min: 500GB) - \(capacity >= minBackupCapacity ? "✅" : "❌")")
        print("   Local: \(isLocal) - \(isLocal ? "✅" : "❌")")
        print("   System volume: \(isSystemVolume(url)) - \(!isSystemVolume(url) ? "✅" : "❌")")
        print("   Writable: \(FileManager.default.isWritableFile(atPath: url.path)) - \(FileManager.default.isWritableFile(atPath: url.path) ? "✅" : "❌")")
        
        guard capacity >= minBackupCapacity else { 
            print("❌ Too small for backup (\(capacityGB)GB < 500GB)")
            return false 
        }
        guard isLocal else { 
            print("❌ Not local")
            return false 
        }
        guard !isSystemVolume(url) else { 
            print("❌ System volume")
            return false 
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else { 
            print("❌ Not writable")
            return false 
        }
        
        print("✅ Qualifies as backup drive")
        return true
    }
    
    #if os(macOS)
    private func isSystemVolume(_ description: [String: Any]) -> Bool {
        // Check if this is a system volume we should ignore
        if let volumeName = description[kDADiskDescriptionVolumeNameKey as String] as? String {
            let systemVolumes = ["Macintosh HD", "System", "Data", "Preboot", "Recovery", "VM", "Update", "Hardware", "xART", "iSCPreboot"]
            if systemVolumes.contains(volumeName) {
                print("🚫 System volume detected by description name: \(volumeName)")
                return true
            }
        }
        
        // Check if volume path indicates system volume
        if let volumePath = description[kDADiskDescriptionVolumePathKey as String] as? URL {
            let path = volumePath.path
            let systemPaths = [
                "/",
                "/System",
                "/System/Volumes/Data",
                "/System/Volumes/Preboot",
                "/System/Volumes/Recovery", 
                "/System/Volumes/Update",
                "/System/Volumes/VM",
                "/System/Volumes/Hardware",
                "/System/Volumes/xarts",
                "/System/Volumes/iSCPreboot"
            ]
            
            if systemPaths.contains(path) || path.hasPrefix("/System/") {
                print("🚫 System volume detected by description path: \(path)")
                return true
            }
        }
        
        return false
    }
    #endif
    
    private func isSystemVolume(_ url: URL) -> Bool {
        let volumeName = url.lastPathComponent
        let path = url.path
        
        // System volume names
        let systemVolumes = ["Macintosh HD", "System", "Data", "Preboot", "Recovery", "VM", "Update", "Hardware", "xART", "iSCPreboot"]
        
        // System paths
        let systemPaths = [
            "/",
            "/System",
            "/System/Volumes/Data",
            "/System/Volumes/Preboot",
            "/System/Volumes/Recovery", 
            "/System/Volumes/Update",
            "/System/Volumes/VM",
            "/System/Volumes/Hardware",
            "/System/Volumes/xarts",
            "/System/Volumes/iSCPreboot"
        ]
        
        // Check volume names
        if systemVolumes.contains(volumeName) {
            print("🚫 System volume detected by name: \(volumeName)")
            return true
        }
        
        // Check system paths
        if systemPaths.contains(path) {
            print("🚫 System volume detected by path: \(path)")
            return true
        }
        
        // Check if it's the user's home directory or system directories
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/Library/") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/") {
            print("🚫 System directory detected: \(path)")
            return true
        }
        
        return false
    }
    
    #if os(macOS)
    private func isDevelopmentOrSimulatorVolume(_ url: URL, description: [String: Any]?) -> Bool {
        let volumeName = url.lastPathComponent
        
        // Check for iOS Simulator volumes
        if volumeName.hasPrefix("iOS_") || volumeName.contains("Simulator") {
            print("🚫 Detected iOS simulator volume: \(volumeName)")
            return true
        }
        
        // Check for other development-related volumes
        let devPrefixes = ["tvOS_", "watchOS_", "visionOS_", "macOS_"]
        for prefix in devPrefixes {
            if volumeName.hasPrefix(prefix) {
                print("🚫 Detected development OS volume: \(volumeName)")
                return true
            }
        }
        
        // Check for Xcode or development paths
        let path = url.path.lowercased()
        let devPaths = ["/library/developer", "/applications/xcode", "coresimulator", "simulator"]
        for devPath in devPaths {
            if path.contains(devPath) {
                print("🚫 Detected development path: \(path)")
                return true
            }
        }
        
        // Check device protocol from DiskArbitration description
        if let deviceProtocol = description?[kDADiskDescriptionDeviceProtocolKey as String] as? String {
            if deviceProtocol.lowercased().contains("virtual") || deviceProtocol.lowercased().contains("simulator") {
                print("🚫 Detected virtual/simulator device protocol: \(deviceProtocol)")
                return true
            }
        }
        
        // Check if device path indicates virtual/development volume
        if let devicePath = description?[kDADiskDescriptionDevicePathKey as String] as? String {
            if devicePath.lowercased().contains("virtual") || devicePath.lowercased().contains("simulator") {
                print("🚫 Detected virtual/simulator device path: \(devicePath)")
                return true
            }
        }
        
        // Check if this is an internal system drive (additional safety check)
        if let deviceInternal = description?[kDADiskDescriptionDeviceInternalKey as String] as? Bool,
           let volumePath = description?[kDADiskDescriptionVolumePathKey as String] as? URL,
           deviceInternal && volumePath.path == "/" {
            print("🚫 Detected internal system drive at root: \(volumePath.path)")
            return true
        }
        
        return false
    }
    #endif
    
    // MARK: - Volume Management
    
    private func addDetectedVolume(_ volume: DetectedVolume) {
        switch volume.type {
        case .cameraCard:
            if !availableCameraCards.contains(where: { $0.devicePath == volume.devicePath }) {
                availableCameraCards.append(volume)
                print("📷 Camera card detected: \(volume.displayName) (\(volume.capacityFormatted))")
            }
        case .backupDrive:
            if !availableBackupDrives.contains(where: { $0.devicePath == volume.devicePath }) {
                availableBackupDrives.append(volume)
                print("💾 Backup drive detected: \(volume.displayName) (\(volume.capacityFormatted))")
            }
        }
    }
    
    private func removeDetectedVolume(devicePath: String) {
        availableCameraCards.removeAll { $0.devicePath == devicePath }
        availableBackupDrives.removeAll { $0.devicePath == devicePath }
        print("📤 Volume removed: \(devicePath)")
    }
    
    // MARK: - Public Methods
    
    func refreshVolumes() {
        scanExistingVolumes()
    }
    
    func forceAnalyzeVolume(at url: URL) {
        print("🔧 Force analyzing volume: \(url)")
        detectionQueue.async { [weak self] in
            #if os(macOS)
            if let detectedVolume = self?.analyzeVolume(at: url, description: nil) {
                DispatchQueue.main.async { [weak self] in
                    self?.addDetectedVolume(detectedVolume)
                }
            }
            #else
            // Volume analysis not available on iOS
            print("⚠️ Force volume analysis not available on iOS")
            #endif
        }
    }
    
    func removeCameraCard(_ volume: DetectedVolume) {
        availableCameraCards.removeAll { $0.id == volume.id }
    }
    
    func removeBackupDrive(_ volume: DetectedVolume) {
        availableBackupDrives.removeAll { $0.id == volume.id }
    }
}