// Core/Services/AnalyticsSharing.swift
import Foundation
import Network

class AnalyticsSharing: ObservableObject {
    static let shared = AnalyticsSharing()
    
    // This would be your actual API endpoint in production
    private let baseURL = "https://api.bitmatch.app/analytics"
    
    @Published var isOptedIn: Bool {
        didSet {
            UserDefaults.standard.set(isOptedIn, forKey: "AnalyticsShareOptIn")
        }
    }
    
    @Published var hasSharedData = false
    
    struct AnonymizedRecord: Codable {
        // Completely anonymized data
        let timestamp: TimeInterval // Unix timestamp
        let fileCount: Int
        let totalSizeGB: Double
        let avgFileSizeMB: Double
        let verificationMode: String
        let sourceSpeed: String
        let destinationSpeed: String
        let actualDurationMinutes: Double
        
        // Hardware context (helps with baseline estimates)
        let platformInfo: PlatformInfo
        
        // No personally identifiable information
        // No file paths, names, or user identifiers
        
        struct PlatformInfo: Codable {
            let osVersion: String // e.g. "macOS 14.0"
            let hardwareModel: String // e.g. "MacBookPro18,1" 
            let processorInfo: String // e.g. "Apple M1 Pro"
            let memoryGB: Int
        }
    }
    
    struct BaselineDataResponse: Codable {
        let success: Bool
        let data: BaselineEstimates?
        let message: String?
        
        struct BaselineEstimates: Codable {
            let averageTimePerFile: [String: Double] // verification mode -> avg seconds per file
            let driveSpeedFactors: [String: Double] // drive type -> performance multiplier
            let fileSizeFactors: [String: Double] // size ranges -> processing time multipliers
            let lastUpdated: TimeInterval
            let sampleSize: Int
        }
    }
    
    private init() {
        self.isOptedIn = UserDefaults.standard.bool(forKey: "AnalyticsShareOptIn")
    }
    
    // MARK: - Data Collection & Sharing
    
    func shareTransferData(_ record: TransferAnalytics.TransferRecord) async {
        guard isOptedIn else { return }
        
        let anonymizedRecord = AnonymizedRecord(
            timestamp: record.timestamp.timeIntervalSince1970,
            fileCount: record.fileCount,
            totalSizeGB: record.totalSizeGB,
            avgFileSizeMB: record.avgFileSizeMB,
            verificationMode: record.verificationMode,
            sourceSpeed: record.sourceSpeed,
            destinationSpeed: record.destinationSpeed,
            actualDurationMinutes: record.actualDurationMinutes,
            platformInfo: getCurrentPlatformInfo()
        )
        
        await uploadAnonymizedData([anonymizedRecord])
    }
    
    func shareAccumulatedData() async {
        guard isOptedIn else { return }
        
        // Get recent records from TransferAnalytics
        
        // Only share data that hasn't been shared yet
        let unsharedRecords = getUnsharedRecords()
        guard !unsharedRecords.isEmpty else { return }
        
        let anonymizedRecords = unsharedRecords.map { record in
            AnonymizedRecord(
                timestamp: record.timestamp.timeIntervalSince1970,
                fileCount: record.fileCount,
                totalSizeGB: record.totalSizeGB,
                avgFileSizeMB: record.avgFileSizeMB,
                verificationMode: record.verificationMode,
                sourceSpeed: record.sourceSpeed,
                destinationSpeed: record.destinationSpeed,
                actualDurationMinutes: record.actualDurationMinutes,
                platformInfo: getCurrentPlatformInfo()
            )
        }
        
        await uploadAnonymizedData(anonymizedRecords)
    }
    
    private func uploadAnonymizedData(_ records: [AnonymizedRecord]) async {
        guard let url = URL(string: "\(baseURL)/contribute") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BitMatch/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let jsonData = try JSONEncoder().encode(records)
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    await MainActor.run {
                        hasSharedData = true
                        markRecordsAsShared(records)
                    }
                    SharedLogger.info("Successfully shared \(records.count) anonymized transfer records", category: .transfer)
                } else {
                    SharedLogger.warning("Failed to share analytics: HTTP \(httpResponse.statusCode)", category: .transfer)
                }
            }
        } catch {
            SharedLogger.error("Error sharing analytics: \(error)", category: .error)
        }
    }
    
    // MARK: - Baseline Data Fetching
    
    func fetchBaselineEstimates() async -> BaselineDataResponse.BaselineEstimates? {
        guard let url = URL(string: "\(baseURL)/baselines") else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let responseData = try JSONDecoder().decode(BaselineDataResponse.self, from: data)
                if responseData.success {
                    SharedLogger.info("Fetched baseline estimates from \(responseData.data?.sampleSize ?? 0) transfers", category: .transfer)
                    return responseData.data
                }
            }
        } catch {
            SharedLogger.error("Error fetching baseline estimates: \(error)", category: .error)
        }
        
        return nil
    }
    
    // MARK: - Privacy & Platform Info
    
    private func getCurrentPlatformInfo() -> AnonymizedRecord.PlatformInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let hardware = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        
        let processInfo = ProcessInfo.processInfo
        let memoryGB = Int(processInfo.physicalMemory / (1024 * 1024 * 1024))
        
        return AnonymizedRecord.PlatformInfo(
            osVersion: "macOS \(processInfo.operatingSystemVersion.majorVersion).\(processInfo.operatingSystemVersion.minorVersion)",
            hardwareModel: hardware,
            processorInfo: getProcessorInfo(),
            memoryGB: memoryGB
        )
    }
    
    private func getProcessorInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        return String(cString: machine)
    }
    
    private func getUnsharedRecords() -> [TransferAnalytics.TransferRecord] {
        // This would need access to TransferAnalytics records
        // For now, return empty array - implement based on your data structure
        return []
    }
    
    private func markRecordsAsShared(_ records: [AnonymizedRecord]) {
        // Mark records as shared to avoid duplicate uploads
        let sharedTimestamps = records.map { $0.timestamp }
        UserDefaults.standard.set(sharedTimestamps, forKey: "SharedAnalyticsTimestamps")
    }
    
    // MARK: - Opt-in/Opt-out UI Support
    
    func showOptInPrompt() -> Bool {
        // Check if user has already been prompted
        return !UserDefaults.standard.bool(forKey: "AnalyticsOptInPromptShown")
    }
    
    func markOptInPromptShown() {
        UserDefaults.standard.set(true, forKey: "AnalyticsOptInPromptShown")
    }
    
    // MARK: - Public Statistics (for transparency)
    
    func getCommunityStats() async -> CommunityStats? {
        guard let url = URL(string: "\(baseURL)/stats") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(CommunityStats.self, from: data)
        } catch {
            SharedLogger.error("Error fetching community stats: \(error)", category: .error)
            return nil
        }
    }
    
    struct CommunityStats: Codable {
        let totalTransfers: Int
        let totalDataProcessedTB: Double
        let averageAccuracyImprovement: Double
        let participatingUsers: Int
        let lastUpdated: TimeInterval
    }
}

// MARK: - Integration with TransferAnalytics

extension TransferAnalytics {
    
    func recordTransferWithSharing(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed,
        actualDurationMinutes: Double
    ) {
        // Record locally first
        recordTransfer(
            fileCount: fileCount,
            totalSizeGB: totalSizeGB,
            verificationMode: verificationMode,
            sourceSpeed: sourceSpeed,
            destinationSpeed: destinationSpeed,
            actualDurationMinutes: actualDurationMinutes
        )
        
        // Share anonymously if opted in
        if AnalyticsSharing.shared.isOptedIn, let lastRecord = lastRecord {
            Task {
                await AnalyticsSharing.shared.shareTransferData(lastRecord)
            }
        }
    }
    
    func getImprovedEstimateWithCommunityData(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed
    ) async -> String {
        
        // First try local data
        let localEstimate = getImprovedEstimate(
            fileCount: fileCount,
            totalSizeGB: totalSizeGB,
            verificationMode: verificationMode,
            sourceSpeed: sourceSpeed,
            destinationSpeed: destinationSpeed
        )
        
        // If we don't have enough local data, use community baselines
        if recordCount < 5 {
            if let baselines = await AnalyticsSharing.shared.fetchBaselineEstimates() {
                return getCommunityBasedEstimate(
                    fileCount: fileCount,
                    totalSizeGB: totalSizeGB,
                    verificationMode: verificationMode,
                    sourceSpeed: sourceSpeed,
                    destinationSpeed: destinationSpeed,
                    baselines: baselines
                )
            }
        }
        
        return localEstimate
    }
    
    private func getCommunityBasedEstimate(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed,
        baselines: AnalyticsSharing.BaselineDataResponse.BaselineEstimates
    ) -> String {
        
        let avgTimePerFile = baselines.averageTimePerFile[verificationMode.rawValue] ?? 0.02
        let driveSpeedFactor = max(100.0, Double(min(sourceSpeed.estimatedSpeed, destinationSpeed.estimatedSpeed))) / 500.0
        
        let estimatedMinutes = Double(fileCount) * (avgTimePerFile / 60.0) * (1.0 / driveSpeedFactor)
        
        return formatDuration(estimatedMinutes)
    }
    
    private func formatDuration(_ minutes: Double) -> String {
        if minutes < 1.0 {
            return "~\(Int(minutes * 60))s"
        } else if minutes < 60.0 {
            return "~\(Int(minutes))m"
        } else {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return mins > 0 ? "~\(hours)h \(mins)m" : "~\(hours)h"
        }
    }
}