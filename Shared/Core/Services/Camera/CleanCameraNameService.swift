// Core/Services/Camera/CleanCameraNameService.swift
import Foundation

/// Service for converting full camera names to clean folder-friendly labels
final class CleanCameraNameService {
    static let shared = CleanCameraNameService()
    private init() {}
    
    // MARK: - Public Interface
    
    func getCleanCameraName(from fullCameraName: String) -> String {
        let cleaned = fullCameraName.uppercased()
        
        // Sony cameras
        if cleaned.contains("SONY") {
            if cleaned.contains("A7S III") || cleaned.contains("A7SM3") { return "A7SIII" }
            if cleaned.contains("A7S II") || cleaned.contains("A7SM2") { return "A7SII" }
            if cleaned.contains("A7S") || cleaned.contains("A7SM") { return "A7S" }
            if cleaned.contains("A7R V") || cleaned.contains("A7RM5") { return "A7RV" }
            if cleaned.contains("A7R IV") || cleaned.contains("A7RM4") { return "A7RIV" }
            if cleaned.contains("A7R III") || cleaned.contains("A7RM3") { return "A7RIII" }
            if cleaned.contains("A7 IV") || cleaned.contains("A7M4") { return "A7IV" }
            if cleaned.contains("A7 III") || cleaned.contains("A7M3") { return "A7III" }
            if cleaned.contains("A7C II") || cleaned.contains("A7CM2") { return "A7CII" }
            if cleaned.contains("A7C") || cleaned.contains("A7CM") { return "A7C" }
            if cleaned.contains("FX-6") || cleaned.contains("FX6") { return "FX6" }
            if cleaned.contains("FX-3") || cleaned.contains("FX3") { return "FX3" }
            if cleaned.contains("FX-30") || cleaned.contains("FX30") { return "FX30" }
            if cleaned.contains("A6700") { return "A6700" }
            if cleaned.contains("A6600") { return "A6600" }
            if cleaned.contains("A6400") { return "A6400" }
            if cleaned.contains("SONY") { return "SONY" }
        }
        
        // Fujifilm cameras
        if cleaned.contains("FUJI") {
            if cleaned.contains("X-T5") || cleaned.contains("XT5") { return "XT5" }
            if cleaned.contains("X-T4") || cleaned.contains("XT4") { return "XT4" }
            if cleaned.contains("X-T3") || cleaned.contains("XT3") { return "XT3" }
            if cleaned.contains("X-T30 II") || cleaned.contains("XT30II") { return "XT30" }
            if cleaned.contains("X-T30") || cleaned.contains("XT30") { return "XT30" }
            if cleaned.contains("X-T20") || cleaned.contains("XT20") { return "XT20" }
            if cleaned.contains("X-H2S") || cleaned.contains("XH2S") { return "XH2S" }
            if cleaned.contains("X-H2") || cleaned.contains("XH2") { return "XH2" }
            if cleaned.contains("X-H1") || cleaned.contains("XH1") { return "XH1" }
            if cleaned.contains("X-PRO3") || cleaned.contains("XPRO3") { return "XPRO3" }
            if cleaned.contains("X-PRO2") || cleaned.contains("XPRO2") { return "XPRO2" }
            if cleaned.contains("X100VI") { return "X100VI" }
            if cleaned.contains("X100F") { return "X100F" }
            if cleaned.contains("X100T") { return "X100T" }
            if cleaned.contains("GFX100S") { return "GFX100S" }
            if cleaned.contains("GFX50S") { return "GFX50S" }
            if cleaned.contains("FUJI") { return "FUJI" }
        }
        
        // Canon cameras
        if cleaned.contains("CANON") {
            if cleaned.contains("EOS R5") || cleaned.contains("R5") { return "R5" }
            if cleaned.contains("EOS R6") || cleaned.contains("R6") { return "R6" }
            if cleaned.contains("EOS R") { return "R" }
            if cleaned.contains("5D MARK IV") || cleaned.contains("5DMKIV") { return "5DMKIV" }
            if cleaned.contains("5D MK IV") { return "5DMKIV" }
            if cleaned.contains("5D4") { return "5DMKIV" }
            if cleaned.contains("1DX MARK III") || cleaned.contains("1DXIII") { return "1DXIII" }
            if cleaned.contains("C70") { return "C70" }
            if cleaned.contains("C300") { return "C300" }
            if cleaned.contains("C500") { return "C500" }
            if cleaned.contains("80D") { return "80D" }
            if cleaned.contains("M50") { return "M50" }
            if cleaned.contains("CANON") { return "CANON" }
        }
        
        // RED cameras
        if cleaned.contains("RED") {
            if cleaned.contains("V-RAPTOR") || cleaned.contains("VRAPTOR") { return "VRAPTOR" }
            if cleaned.contains("KOMODO") { return "KOMODO" }
            if cleaned.contains("EPIC") { return "EPIC" }
            if cleaned.contains("DRAGON") { return "DRAGON" }
            if cleaned.contains("RED") { return "RED" }
        }
        
        // ARRI cameras
        if cleaned.contains("ARRI") {
            if cleaned.contains("ALEXA MINI LF") { return "ALXMINILF" }
            if cleaned.contains("ALEXA MINI") { return "ALXMINI" }
            if cleaned.contains("ALEXA LF") { return "ALXLF" }
            if cleaned.contains("ALEXA") { return "ALEXA" }
            if cleaned.contains("AMIRA") { return "AMIRA" }
            if cleaned.contains("ARRI") { return "ARRI" }
        }
        
        // Blackmagic cameras
        if cleaned.contains("BLACKMAGIC") {
            if cleaned.contains("POCKET CINEMA") || cleaned.contains("POCKET") { return "BMPCC" }
            if cleaned.contains("URSA MINI PRO") { return "URSAMINI" }
            if cleaned.contains("URSA") { return "URSA" }
            if cleaned.contains("BLACKMAGIC") { return "BMD" }
        }
        
        // DJI cameras
        if cleaned.contains("DJI") {
            if cleaned.contains("MINI 4 PRO") || cleaned.contains("MINI4PRO") { return "MINI4PRO" }
            if cleaned.contains("MINI 3 PRO") || cleaned.contains("MINI3PRO") { return "MINI3PRO" }
            if cleaned.contains("MINI 3") || cleaned.contains("MINI3") { return "MINI3" }
            if cleaned.contains("MINI 2") || cleaned.contains("MINI2") { return "MINI2" }
            if cleaned.contains("AIR 3") || cleaned.contains("AIR3") { return "AIR3" }
            if cleaned.contains("AIR 2S") || cleaned.contains("AIR2S") { return "AIR2S" }
            if cleaned.contains("MAVIC") { return "MAVIC" }
            if cleaned.contains("INSPIRE") { return "INSPIRE" }
            if cleaned.contains("DJI") { return "DJI" }
        }
        
        // GoPro cameras
        if cleaned.contains("GOPRO") {
            if cleaned.contains("HERO12") || cleaned.contains("HERO 12") { return "GP12" }
            if cleaned.contains("HERO11") || cleaned.contains("HERO 11") { return "GP11" }
            if cleaned.contains("HERO10") || cleaned.contains("HERO 10") { return "GP10" }
            if cleaned.contains("HERO9") || cleaned.contains("HERO 9") { return "GP9" }
            if cleaned.contains("HERO8") || cleaned.contains("HERO 8") { return "GP8" }
            if cleaned.contains("MAX") { return "GPMAX" }
            if cleaned.contains("GOPRO") { return "GP" }
        }
        
        // iPhone/Apple
        if cleaned.contains("IPHONE") {
            if cleaned.contains("15 PRO MAX") { return "IP15PM" }
            if cleaned.contains("15 PRO") { return "IP15P" }
            if cleaned.contains("15 PLUS") { return "IP15PL" }
            if cleaned.contains("15") { return "IP15" }
            if cleaned.contains("14 PRO MAX") { return "IP14PM" }
            if cleaned.contains("14 PRO") { return "IP14P" }
            if cleaned.contains("14") { return "IP14" }
            if cleaned.contains("IPHONE") { return "IPHONE" }
        }
        
        // Panasonic cameras
        if cleaned.contains("PANASONIC") {
            if cleaned.contains("GH6") { return "GH6" }
            if cleaned.contains("GH5") { return "GH5" }
            if cleaned.contains("S1H") { return "S1H" }
            if cleaned.contains("S5") { return "S5" }
            if cleaned.contains("G9") { return "G9" }
            if cleaned.contains("PANASONIC") { return "PANA" }
        }
        
        // Nikon cameras
        if cleaned.contains("NIKON") {
            if cleaned.contains("Z9") { return "Z9" }
            if cleaned.contains("Z8") { return "Z8" }
            if cleaned.contains("Z6 II") { return "Z6II" }
            if cleaned.contains("Z6") { return "Z6" }
            if cleaned.contains("Z5") { return "Z5" }
            if cleaned.contains("D850") { return "D850" }
            if cleaned.contains("NIKON") { return "NIKON" }
        }
        
        // Default: Clean up the original name
        var result = fullCameraName
        result = result.replacingOccurrences(of: "-", with: "")
        result = result.replacingOccurrences(of: " ", with: "")
        result = result.replacingOccurrences(of: "Mark", with: "MK", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "III", with: "3")
        result = result.replacingOccurrences(of: "II", with: "2")
        
        return result.prefix(8).uppercased().description // Limit to 8 characters for folder names
    }
}