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
        let estimate = estimateMinutes(
            fileCount: fileCount,
            totalSizeGB: totalSizeGB,
            verificationMode: verificationMode,
            sourceSpeed: sourceSpeed,
            destinationSpeed: destinationSpeed,
            history: records
        )
        return formatDuration(estimate)
    }
    
    private func estimateMinutes(
        fileCount: Int,
        totalSizeGB: Double,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed,
        history: [TransferRecord]
    ) -> Double {
        // Try to find similar transfers
        let similarTransfers = history.filter { record in
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
            // Weighted estimate where closer historical transfers contribute more.
            let weighted = similarTransfers.map { record -> (minutes: Double, weight: Double) in
                let sizeDenominator = max(totalSizeGB, record.totalSizeGB, 0.001)
                let sizeSimilarity = max(0.0, 1.0 - abs(record.totalSizeGB - totalSizeGB) / sizeDenominator)
                let countDenominator = max(Double(fileCount), Double(record.fileCount), 1.0)
                let countSimilarity = max(0.0, 1.0 - abs(Double(record.fileCount - fileCount)) / countDenominator)
                let weight = max(0.05, (sizeSimilarity + countSimilarity) / 2.0)
                return (record.actualDurationMinutes, weight)
            }
            let totalWeight = weighted.reduce(0.0) { $0 + $1.weight }
            if totalWeight > 0 {
                let weightedMinutes = weighted.reduce(0.0) { $0 + ($1.minutes * $1.weight) } / totalWeight
                return max(0.0, weightedMinutes)
            }
        }

        // Fallback to calibrated baseline if no similar transfers.
        return calibratedEstimateMinutes(
            fileCount: fileCount,
            verificationMode: verificationMode,
            sourceSpeed: sourceSpeed,
            destinationSpeed: destinationSpeed,
            history: history
        )
    }

    private func calibratedEstimateMinutes(
        fileCount: Int,
        verificationMode: VerificationMode,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        destinationSpeed: FileSelectionViewModel.DriveSpeed,
        history: [TransferRecord]
    ) -> Double {
        // Calibrated based on average performance data from all recorded transfers.
        let avgTimePerFile = history.isEmpty
            ? 0.02
            : history.map { $0.actualDurationMinutes / max(Double($0.fileCount), 1.0) }.reduce(0, +) / Double(history.count)

        let complexityFactor: Double
        switch verificationMode {
        case .quick: complexityFactor = 0.1
        case .standard: complexityFactor = 1.0  
        case .thorough: complexityFactor = 1.8
        case .paranoid: complexityFactor = 2.5
        }
        
        let driveSpeedFactor = max(100.0, Double(min(sourceSpeed.estimatedSpeed, destinationSpeed.estimatedSpeed))) / 500.0
        let estimatedMinutes = Double(fileCount) * avgTimePerFile * complexityFactor * (1.0 / driveSpeedFactor)
        return max(0.0, estimatedMinutes)
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
        // Compare historical predictions to actual durations.
        // For each record, predict using only prior records to avoid
        // self-referential bias.
        guard records.count >= 2 else { return 0 }

        var accuracySamples: [Double] = []
        for (index, record) in records.enumerated() where index > 0 {
            guard let mode = VerificationMode(rawValue: record.verificationMode) else { continue }
            let sourceSpeed = FileSelectionViewModel.DriveSpeed(rawValue: record.sourceSpeed) ?? .unknown
            let destinationSpeed = FileSelectionViewModel.DriveSpeed(rawValue: record.destinationSpeed) ?? .unknown
            let history = Array(records[..<index])
            guard !history.isEmpty else { continue }

            let estimatedMinutes = estimateMinutes(
                fileCount: record.fileCount,
                totalSizeGB: record.totalSizeGB,
                verificationMode: mode,
                sourceSpeed: sourceSpeed,
                destinationSpeed: destinationSpeed,
                history: history
            )

            let actualMinutes = max(record.actualDurationMinutes, 0.001)
            let relativeError = abs(estimatedMinutes - actualMinutes) / actualMinutes
            let accuracy = max(0.0, 1.0 - relativeError)
            accuracySamples.append(accuracy)
        }

        guard !accuracySamples.isEmpty else { return 0 }
        return accuracySamples.reduce(0.0, +) / Double(accuracySamples.count)
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
