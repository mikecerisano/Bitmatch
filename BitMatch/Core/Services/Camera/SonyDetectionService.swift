// Core/Services/Camera/SonyDetectionService.swift
import Foundation

/// Specialized service for detecting Sony cameras via MEDIAPRO.XML and folder structure
final class SonyDetectionService {
    static let shared = SonyDetectionService()
    private init() {}
    
    // MARK: - Public Interface
    
    func detectSonyCamera(at url: URL) -> String? {
        if let xmlInfo = checkSonyMediaProXML(at: url) {
            return xmlInfo
        }
        
        if let folderInfo = checkSonyFolderStructure(at: url) {
            return folderInfo
        }
        
        return nil
    }
    
    // MARK: - MEDIAPRO.XML Detection
    
    private func checkSonyMediaProXML(at url: URL) -> String? {
        // Check both consumer (M4ROOT) and pro (XDROOT) locations
        let candidatePaths = [
            "PRIVATE/M4ROOT/MEDIAPRO.XML",
            "XDROOT/MEDIAPRO.XML"
        ]
        
        guard let mediaProPath = candidatePaths
                .map({ url.appendingPathComponent($0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        
        do {
            let xmlString = try String(contentsOf: mediaProPath, encoding: .utf8)
            
            if let systemIdRange = xmlString.range(of: #"systemId="([^"]+)""#, options: .regularExpression) {
                let systemId = String(xmlString[systemIdRange])
                    .replacingOccurrences(of: #"systemId=""#, with: "")
                    .replacingOccurrences(of: "\"", with: "")
                
                if let cameraModel = mapSonySystemId(systemId) {
                    return "Sony \(cameraModel)"
                }
            }
            
            if let systemKindRange = xmlString.range(of: #"systemKind="([^"]+)""#, options: .regularExpression) {
                // Extract attribute value
                var systemKind = String(xmlString[systemKindRange])
                systemKind = systemKind.replacingOccurrences(of: #"systemKind=""#, with: "")
                                       .replacingOccurrences(of: "\"", with: "")
                                       .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let cameraModel = mapSonySystemKind(systemKind) {
                    SharedLogger.info("Resolved model: \(cameraModel) from systemKind=\(systemKind) at \(mediaProPath.path)", category: .transfer)
                    return "Sony \(cameraModel)"
                }
            }
            
            return "Sony"
            
        } catch {
            return nil
        }
    }
    
    // MARK: - Sony Folder Structure Detection
    
    private func checkSonyFolderStructure(at url: URL) -> String? {
        let fm = FileManager.default
        
        let sonyIndicators = [
            // Consumer/Prosumer
            "PRIVATE/M4ROOT",
            "PRIVATE/AVCHD",
            "DCIM",
            "MP_ROOT/101PNV01",
            // Professional XAVC (FX6/FX9/FS7)
            "XDROOT",
            "XDROOT/Clip",
            "XDROOT/General",
            "XDROOT/Sub"
        ]
        
        var foundIndicators = 0
        for indicator in sonyIndicators {
            let indicatorPath = url.appendingPathComponent(indicator)
            if fm.fileExists(atPath: indicatorPath.path) {
                foundIndicators += 1
            }
        }
        
        // If XDROOT is present at all, treat as Sony XAVC
        if fm.fileExists(atPath: url.appendingPathComponent("XDROOT").path) {
            return "Sony"
        }
        
        return foundIndicators >= 2 ? "Sony" : nil
    }
    
    // MARK: - System ID/Kind Mapping
    
    private func mapSonySystemId(_ systemId: String) -> String? {
        let idMapping: [String: String] = [
            "0x0123": "A7S III",
            "0x0124": "A7S II",
            "0x0125": "A7S",
            "0x0126": "FX6",
            "0x0127": "FX3",
            "0x0128": "A7R V",
            "0x0129": "A7R IV",
            "0x012A": "A7 IV",
            "0x012B": "A7C II",
            "0x012C": "A7C",
            "0x012D": "FX30",
            "0x012E": "A6700",
            "0x012F": "A6600",
            "0x0130": "A6400"
        ]
        
        return idMapping[systemId]
    }
    
    private func mapSonySystemKind(_ systemKind: String) -> String? {
        let kindMapping: [String: String] = [
            "ILCE-7SM3": "A7S III",
            "ILCE-7SM2": "A7S II",
            "ILCE-7S": "A7S",
            "ILCE-7RM5": "A7R V",
            "ILCE-7RM4": "A7R IV",
            "ILCE-7M4": "A7 IV",
            "ILCE-7C": "A7C",
            // Cinema line
            "ILME-FX6": "FX6",
            "ILME-FX3": "FX3",
            "ILME-FX30": "FX30",
            "ILME-FX9": "FX9",
            // XDCAM PXW series common on pro media
            "PXW-FS7": "FS7",
            "PXW-FS7M2": "FS7 II",
            "PXW-FS5": "FS5",
            "ILCE-6700": "A6700",
            "ILCE-6600": "A6600",
            "ILCE-6400": "A6400"
        ]
        // Allow partial match (e.g., "ILME-FX6V ver.5.010" contains "ILME-FX6")
        for (key, val) in kindMapping {
            if systemKind.localizedCaseInsensitiveContains(key) { return val }
        }
        return nil
    }
}
