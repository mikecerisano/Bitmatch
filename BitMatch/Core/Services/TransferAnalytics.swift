// Core/Services/TransferAnalytics.swift
import Foundation

class TransferAnalytics: ObservableObject {
    static let shared = TransferAnalytics()
    
    private let analyticsKey = "BitMatchTransferAnalytics"
    
    struct TransferRecord: Codable {
        let timestamp: Date
        let fileCount: Int
        let totalSizeGB: Double
        let verificationMode: String
        let sourceSpeed: String
        let destinationSpeed: String
        let actualDurationMinutes: Double
        let avgFileSizeMB: Double
    }
    
    @Published private var records: [TransferRecord] = []
    
    private init() {
        loadRecords()
    }
    
    // MARK: - Recording Transfer Data
    
    func recordTransfer(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed,
        actualDurationMinutes: Double
    ) {
        let record = TransferRecord(
            timestamp: Date(),
            fileCount: fileCount,
            totalSizeGB: totalSizeGB,
            verificationMode: verificationMode.rawValue,
            sourceSpeed: sourceSpeed.rawValue,
            destinationSpeed: destinationSpeed.rawValue,
            actualDurationMinutes: actualDurationMinutes,
            avgFileSizeMB: (totalSizeGB * 1024) / max(Double(fileCount), 1)
        )
        
        records.append(record)
        
        // Keep only recent 100 records for performance
        if records.count > 100 {
            records = Array(records.suffix(100))
        }
        
        saveRecords()
        SharedLogger.info("Recorded transfer: \(fileCount) files, \(String(format: "%.1f", totalSizeGB))GB in \(String(format: "%.1f", actualDurationMinutes))m", category: .transfer)
    }
    
    // MARK: - Improved Time Estimation
    
    func getImprovedEstimate(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed
    ) -> String {
        
        // Try to find similar transfers
        let similarTransfers = records.filter { record in
            // Match verification mode
            record.verificationMode == verificationMode.rawValue &&
            // Similar file count (within 50%)
            abs(record.fileCount - fileCount) <= fileCount / 2 &&
            // Similar total size (within 50%)
            abs(record.totalSizeGB - totalSizeGB) <= totalSizeGB * 0.5 &&
            // Same or similar drive speeds
            (record.sourceSpeed == sourceSpeed.rawValue || record.destinationSpeed == destinationSpeed.rawValue)
        }
        
        if !similarTransfers.isEmpty {
            // Use machine learning approach: weighted average based on similarity
            let weightedEstimate = similarTransfers.map { record in
                let sizeSimilarity = 1.0 - abs(record.totalSizeGB - totalSizeGB) / max(totalSizeGB, record.totalSizeGB)
                let countSimilarity = 1.0 - abs(Double(record.fileCount - fileCount)) / max(Double(fileCount), Double(record.fileCount))
                let weight = (sizeSimilarity + countSimilarity) / 2.0
                return record.actualDurationMinutes * weight
            }.reduce(0, +) / Double(similarTransfers.count)
            
            return formatDuration(weightedEstimate)
        }
        
        // Fallback to calibrated baseline if no similar transfers
        return getCalibratedEstimate(
            fileCount: fileCount,
            totalSizeGB: totalSizeGB,
            verificationMode: verificationMode,
            sourceSpeed: sourceSpeed,
            destinationSpeed: destinationSpeed
        )
    }
    
    private func getCalibratedEstimate(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed
    ) -> String {
        
        // Calibrated based on average performance data from all recorded transfers
        let avgTimePerFile = records.isEmpty ? 0.02 : records.map { $0.actualDurationMinutes / Double($0.fileCount) }.reduce(0, +) / Double(records.count)
        
        let complexityFactor: Double
        switch verificationMode {
        case .quick: complexityFactor = 0.1
        case .standard: complexityFactor = 1.0  
        case .thorough: complexityFactor = 1.8
        case .paranoid: complexityFactor = 2.5
        }
        
        let driveSpeedFactor = max(100.0, Double(min(sourceSpeed.estimatedSpeed, destinationSpeed.estimatedSpeed))) / 500.0
        let estimatedMinutes = Double(fileCount) * avgTimePerFile * complexityFactor * (1.0 / driveSpeedFactor)
        
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
    
    // MARK: - Statistics
    
    var totalTransfersRecorded: Int {
        records.count
    }
    
    var lastRecord: TransferRecord? {
        records.last
    }
    
    var recordCount: Int {
        records.count
    }
    
    var averageAccuracy: Double {
        guard !records.isEmpty else { return 0 }
        // This would require comparing estimates vs actual - TODO
        return 0.85 // Placeholder
    }
    
    // MARK: - Persistence
    
    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: analyticsKey),
           let decoded = try? JSONDecoder().decode([TransferRecord].self, from: data) {
            records = decoded
        }
    }
    
    private func saveRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: analyticsKey)
        }
    }
}