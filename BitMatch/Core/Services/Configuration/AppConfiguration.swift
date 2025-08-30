// Core/Services/Configuration/AppConfiguration.swift
import Foundation

/// Centralized app configuration management
class AppConfiguration: ObservableObject {
    static let shared = AppConfiguration()
    
    // MARK: - Transfer Settings
    @Published var maxConcurrentTransfers: Int = 3 {
        didSet { UserDefaults.standard.set(maxConcurrentTransfers, forKey: Keys.maxConcurrentTransfers) }
    }
    
    @Published var verificationEnabled: Bool = true {
        didSet { UserDefaults.standard.set(verificationEnabled, forKey: Keys.verificationEnabled) }
    }
    
    @Published var checksumAlgorithm: ChecksumAlgorithm = .xxHash {
        didSet { UserDefaults.standard.set(checksumAlgorithm.rawValue, forKey: Keys.checksumAlgorithm) }
    }
    
    // MARK: - UI Settings
    @Published var showDetailedProgress: Bool = true {
        didSet { UserDefaults.standard.set(showDetailedProgress, forKey: Keys.showDetailedProgress) }
    }
    
    @Published var autoCloseOnComplete: Bool = false {
        didSet { UserDefaults.standard.set(autoCloseOnComplete, forKey: Keys.autoCloseOnComplete) }
    }
    
    // MARK: - Performance Settings
    @Published var bufferSize: Int = 1_048_576 { // 1MB default
        didSet { UserDefaults.standard.set(bufferSize, forKey: Keys.bufferSize) }
    }
    
    @Published var enableAnalytics: Bool = false {
        didSet { UserDefaults.standard.set(enableAnalytics, forKey: Keys.enableAnalytics) }
    }
    
    enum ChecksumAlgorithm: String, CaseIterable {
        case md5 = "MD5"
        case sha256 = "SHA256"
        case xxHash = "xxHash"
        
        var displayName: String {
            switch self {
            case .md5: return "MD5 (Fast)"
            case .sha256: return "SHA256 (Secure)"
            case .xxHash: return "xxHash (Fastest)"
            }
        }
    }
    
    private enum Keys {
        static let maxConcurrentTransfers = "MaxConcurrentTransfers"
        static let verificationEnabled = "VerificationEnabled"
        static let checksumAlgorithm = "ChecksumAlgorithm"
        static let showDetailedProgress = "ShowDetailedProgress"
        static let autoCloseOnComplete = "AutoCloseOnComplete"
        static let bufferSize = "BufferSize"
        static let enableAnalytics = "EnableAnalytics"
    }
    
    private init() {
        loadSettings()
        AppLogger.info("App configuration loaded", category: .general)
    }
    
    private func loadSettings() {
        maxConcurrentTransfers = UserDefaults.standard.integer(forKey: Keys.maxConcurrentTransfers) != 0 
            ? UserDefaults.standard.integer(forKey: Keys.maxConcurrentTransfers) : 3
        
        verificationEnabled = UserDefaults.standard.bool(forKey: Keys.verificationEnabled)
        
        if let algorithmString = UserDefaults.standard.string(forKey: Keys.checksumAlgorithm),
           let algorithm = ChecksumAlgorithm(rawValue: algorithmString) {
            checksumAlgorithm = algorithm
        }
        
        showDetailedProgress = UserDefaults.standard.bool(forKey: Keys.showDetailedProgress)
        autoCloseOnComplete = UserDefaults.standard.bool(forKey: Keys.autoCloseOnComplete)
        
        bufferSize = UserDefaults.standard.integer(forKey: Keys.bufferSize) != 0 
            ? UserDefaults.standard.integer(forKey: Keys.bufferSize) : 1_048_576
        
        enableAnalytics = UserDefaults.standard.bool(forKey: Keys.enableAnalytics)
    }
    
    func resetToDefaults() {
        maxConcurrentTransfers = 3
        verificationEnabled = true
        checksumAlgorithm = .xxHash
        showDetailedProgress = true
        autoCloseOnComplete = false
        bufferSize = 1_048_576
        enableAnalytics = false
        
        AppLogger.info("App configuration reset to defaults", category: .general)
    }
}