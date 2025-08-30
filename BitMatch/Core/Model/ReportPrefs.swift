import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum ChecksumAlgorithm: String, CaseIterable, Identifiable {
    case md5 = "MD5"
    case sha256 = "SHA-256"
    var id: Self { self }
}

enum PrefKey {
    static let makeReport = "report.make"
    static let client     = "report.client"
    static let production = "report.production"
    static let company    = "report.company"
    static let verifyWithChecksum = "checksum.verify"
    static let checksumAlgorithm = "checksum.algorithm"
    static let clientLogoData = "report.clientLogoData"
    static let companyLogoData = "report.companyLogoData"
    static let hasLaunchedBefore = "app.hasLaunchedBefore"
    
    // Camera detection preferences
    static let enableAutoCameraDetection = "camera.enableAutoDetection"
    static let autoPopulateSource = "camera.autoPopulateSource"
    static let showCameraDetectionNotifications = "camera.showNotifications"
}

// Make the class conform to ObservableObject
final class ReportPrefs: ObservableObject {
    private let d = UserDefaults.standard

    // Use @Published and didSet to automatically save any changes
    @Published var makeReport: Bool {
        didSet { d.set(makeReport, forKey: PrefKey.makeReport) }
    }
    @Published var client: String {
        didSet { d.set(client, forKey: PrefKey.client) }
    }
    @Published var production: String {
        didSet { d.set(production, forKey: PrefKey.production) }
    }
    @Published var company: String {
        didSet { d.set(company, forKey: PrefKey.company) }
    }
    @Published var verifyWithChecksum: Bool {
        didSet { d.set(verifyWithChecksum, forKey: PrefKey.verifyWithChecksum) }
    }
    @Published var checksumAlgorithm: ChecksumAlgorithm {
        didSet { d.set(checksumAlgorithm.rawValue, forKey: PrefKey.checksumAlgorithm) }
    }
    
    // Camera detection preferences
    @Published var enableAutoCameraDetection: Bool {
        didSet { d.set(enableAutoCameraDetection, forKey: PrefKey.enableAutoCameraDetection) }
    }
    @Published var autoPopulateSource: Bool {
        didSet { d.set(autoPopulateSource, forKey: PrefKey.autoPopulateSource) }
    }
    @Published var showCameraDetectionNotifications: Bool {
        didSet { d.set(showCameraDetectionNotifications, forKey: PrefKey.showCameraDetectionNotifications) }
    }
    
    // Logo data properties (stored as Data in UserDefaults)
    @Published var clientLogoData: Data? {
        didSet {
            if let data = clientLogoData {
                d.set(data, forKey: PrefKey.clientLogoData)
            } else {
                d.removeObject(forKey: PrefKey.clientLogoData)
            }
        }
    }
    
    @Published var companyLogoData: Data? {
        didSet {
            if let data = companyLogoData {
                d.set(data, forKey: PrefKey.companyLogoData)
            } else {
                d.removeObject(forKey: PrefKey.companyLogoData)
            }
        }
    }
    
    // Computed properties for cross-platform image access
    #if os(macOS)
    var clientLogoImage: NSImage? {
        get {
            guard let data = clientLogoData else { return nil }
            return NSImage(data: data)
        }
        set {
            objectWillChange.send()
            clientLogoData = newValue?.tiffRepresentation
        }
    }
    
    var companyLogoImage: NSImage? {
        get {
            guard let data = companyLogoData else { return nil }
            return NSImage(data: data)
        }
        set {
            objectWillChange.send()
            companyLogoData = newValue?.tiffRepresentation
        }
    }
    #else
    var clientLogoImage: UIImage? {
        get {
            guard let data = clientLogoData else { return nil }
            return UIImage(data: data)
        }
        set {
            objectWillChange.send()
            clientLogoData = newValue?.pngData()
        }
    }
    
    var companyLogoImage: UIImage? {
        get {
            guard let data = companyLogoData else { return nil }
            return UIImage(data: data)
        }
        set {
            objectWillChange.send()
            companyLogoData = newValue?.pngData()
        }
    }
    #endif

    // An initializer to load the saved values when the app starts
    init() {
        // Check if this is the first launch
        let hasLaunchedBefore = d.bool(forKey: PrefKey.hasLaunchedBefore)
        
        if !hasLaunchedBefore {
            // First launch - set defaults
            d.set(true, forKey: PrefKey.hasLaunchedBefore)
            self.makeReport = false  // Default to OFF
            self.client = ""
            self.production = ""
            self.company = ""
            self.verifyWithChecksum = false
            self.checksumAlgorithm = .sha256
            self.clientLogoData = nil
            self.companyLogoData = nil
            
            // Camera detection defaults
            self.enableAutoCameraDetection = true  // Default to ON for better UX
            self.autoPopulateSource = true         // Auto-populate when detected
            self.showCameraDetectionNotifications = true
        } else {
            // Not first launch - load saved values
            self.makeReport = d.bool(forKey: PrefKey.makeReport)
            self.client = d.string(forKey: PrefKey.client) ?? ""
            self.production = d.string(forKey: PrefKey.production) ?? ""
            self.company = d.string(forKey: PrefKey.company) ?? ""
            self.verifyWithChecksum = d.bool(forKey: PrefKey.verifyWithChecksum)
            
            if let savedAlgo = d.string(forKey: PrefKey.checksumAlgorithm) {
                self.checksumAlgorithm = ChecksumAlgorithm(rawValue: savedAlgo) ?? .sha256
            } else {
                self.checksumAlgorithm = .sha256
            }
            
            self.clientLogoData = d.data(forKey: PrefKey.clientLogoData)
            self.companyLogoData = d.data(forKey: PrefKey.companyLogoData)
            
            // Camera detection preferences
            self.enableAutoCameraDetection = d.bool(forKey: PrefKey.enableAutoCameraDetection)
            self.autoPopulateSource = d.bool(forKey: PrefKey.autoPopulateSource)
            self.showCameraDetectionNotifications = d.bool(forKey: PrefKey.showCameraDetectionNotifications)
        }
    }
}
