// Core/Models/ModelTypes.swift
import Foundation

// MARK: - Camera Type Enum
enum CameraType: String, CaseIterable {
    case generic = "Camera"
    case arriAlexa = "ARRI ALEXA"
    case arriAmira = "ARRI AMIRA"
    case redDragon = "RED Dragon"
    case sonyFX6 = "Sony FX6"
    case sonyFX3 = "Sony FX3"
    case sonyA7S = "Sony A7S"
    case canonC70 = "Canon C70"
    case blackmagicPocket = "Blackmagic Pocket"
    case dji = "DJI"
    case gopro = "GoPro"
    
    var icon: String {
        switch self {
        case .arriAlexa, .arriAmira, .redDragon: return "film"
        case .dji: return "airplane"
        case .gopro: return "video.circle"
        default: return "camera.fill"
        }
    }
}

// MARK: - Verification Mode Enum
enum VerificationMode: String, CaseIterable, Identifiable {
    case quick = "Fast Check"              // Changed from "Quick (Size Only)"
    case standard = "Safe"                 // Changed from "Standard (Byte Compare)"
    case thorough = "Bulletproof"          // Changed from "Thorough (SHA-256)"
    case paranoid = "Maximum (Netflix/MHL)" // Changed from "Paranoid (SHA-256 + Byte)"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .quick: return "Size comparison only - fastest"
        case .standard: return "Byte-by-byte - recommended"
        case .thorough: return "SHA-256 checksum - secure"
        case .paranoid: return "Checksum + byte compare - production standard"
        }
    }
    
    var useChecksum: Bool {
        switch self {
        case .quick, .standard: return false
        case .thorough, .paranoid: return true
        }
    }
    
    // Add MHL detection
    var requiresMHL: Bool {
        return self == .paranoid
    }
    
    // Time estimation based on verification complexity and drive characteristics
    func estimatedDuration(
        fileCount: Int,
        totalSizeGB: Double,
        sourceSpeed: FileSelectionViewModel.DriveSpeed,
        fastestDestSpeed: FileSelectionViewModel.DriveSpeed
    ) -> String {
        let avgFileSizeMB = totalSizeGB * 1024 / max(Double(fileCount), 1)
        
        // Base factors for different verification modes
        let complexityFactor: Double
        
        switch self {
        case .quick:
            complexityFactor = 0.1  // Just file size checks
        case .standard:
            complexityFactor = 1.0  // Byte-by-byte comparison
        case .thorough:
            complexityFactor = 1.8  // SHA-256 computation
        case .paranoid:
            complexityFactor = 2.5  // SHA-256 + byte compare + MHL generation
        }
        
        // Drive speed impact (slower drives = longer verification)
        let driveSpeedFactor = max(100.0, Double(min(sourceSpeed.estimatedSpeed, fastestDestSpeed.estimatedSpeed))) / 500.0
        
        // File size impact (larger files = longer per-file processing)
        let fileSizeFactor = max(0.5, min(2.0, avgFileSizeMB / 50.0)) // 50MB baseline
        
        // Calculate estimated time in minutes
        let baseTimeMinutes = Double(fileCount) * 0.02 // ~1.2 seconds per file baseline
        let adjustedTimeMinutes = baseTimeMinutes * complexityFactor * (1.0 / driveSpeedFactor) * fileSizeFactor
        
        if adjustedTimeMinutes < 1.0 {
            return "~\(Int(adjustedTimeMinutes * 60))s"
        } else if adjustedTimeMinutes < 60.0 {
            return "~\(Int(adjustedTimeMinutes))m"
        } else {
            let hours = Int(adjustedTimeMinutes / 60)
            let minutes = Int(adjustedTimeMinutes.truncatingRemainder(dividingBy: 60))
            return minutes > 0 ? "~\(hours)h \(minutes)m" : "~\(hours)h"
        }
    }
}
