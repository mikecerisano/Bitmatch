// SharedReportGenerationService.swift - Unified report generation for iOS and macOS
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
class SharedReportGenerationService: ObservableObject {
    
    // MARK: - Report Configuration
    
    struct ReportConfiguration {
        let production: String
        let client: String
        let company: String
        let technician: String
        let productionNotes: String
        let includeThumbnails: Bool
        let logoPath: String?
        
        // Visual styling
        let primaryColor: String
        let secondaryColor: String
        let fontFamily: String
        let fontSize: CGFloat
        let margins: ReportMargins
        
        struct ReportMargins {
            let top: CGFloat
            let bottom: CGFloat
            let left: CGFloat
            let right: CGFloat
            
            static let standard = ReportMargins(top: 50, bottom: 50, left: 50, right: 50)
        }
        
        static func `default`() -> ReportConfiguration {
            return ReportConfiguration(
                production: "",
                client: "",
                company: "",
                technician: "",
                productionNotes: "",
                includeThumbnails: false,
                logoPath: nil,
                primaryColor: "#007AFF",
                secondaryColor: "#8E8E93",
                fontFamily: "Helvetica",
                fontSize: 10,
                margins: .standard
            )
        }
    }
    
    // MARK: - Master Report Generation
    
    func generateMasterReport(
        transfers: [TransferCard],
        configuration: ReportConfiguration
    ) async throws -> MasterReportResult {
        
        let reportData = generateReportData(transfers: transfers, configuration: configuration)
        let pdfData = try await generatePDF(from: reportData, configuration: configuration)
        let jsonData = try generateJSON(transfers: transfers, configuration: configuration)
        
        return MasterReportResult(
            pdfData: pdfData,
            jsonData: jsonData,
            reportData: reportData,
            generatedAt: Date()
        )
    }
    
    // MARK: - Report Data Generation
    
    private func generateReportData(transfers: [TransferCard], configuration: ReportConfiguration) -> ReportData {
        let totalSize = transfers.reduce(0) { $0 + $1.totalSize }
        let totalFiles = transfers.reduce(0) { $0 + $1.fileCount }
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        
        // Group transfers by camera for better organization
        let cameraGroups = Dictionary(grouping: transfers) { $0.cameraName }
            .map { (cameraName, transfers) in
                ReportData.CameraGroup(
                    cameraName: cameraName,
                    transfers: transfers,
                    totalFiles: transfers.reduce(0) { $0 + $1.fileCount },
                    totalSize: transfers.reduce(0) { $0 + $1.totalSize }
                )
            }
            .sorted { $0.cameraName < $1.cameraName }
        
        return ReportData(
            configuration: configuration,
            generatedAt: Date(),
            summary: ReportData.Summary(
                totalTransfers: transfers.count,
                totalFiles: totalFiles,
                totalSize: totalSize,
                formattedSize: formattedSize,
                verificationRate: calculateVerificationRate(transfers: transfers)
            ),
            cameraGroups: cameraGroups,
            allTransfers: transfers
        )
    }
    
    // MARK: - PDF Generation
    
    private func generatePDF(from reportData: ReportData, configuration: ReportConfiguration) async throws -> Data {
        #if os(macOS)
        return try await generateMacOSPDF(from: reportData, configuration: configuration)
        #else
        return try await generateIOSPDF(from: reportData, configuration: configuration)
        #endif
    }
    
    #if os(macOS)
    private func generateMacOSPDF(from reportData: ReportData, configuration: ReportConfiguration) async throws -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "BitMatch",
            kCGPDFContextTitle: "Master Transfer Report",
            kCGPDFContextSubject: "Production: \(configuration.production)",
            kCGPDFContextAuthor: configuration.company
        ] as CFDictionary
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let mutableData = NSMutableData()
        
        guard let context = CGContext(consumer: CGDataConsumer(data: mutableData)!,
                                    mediaBox: &pageRect.pointee,
                                    pdfMetaData) else {
            throw ReportGenerationError.pdfCreationFailed
        }
        
        try await renderPDFContent(context: context, reportData: reportData, configuration: configuration, pageRect: pageRect)
        
        return mutableData as Data
    }
    #endif
    
    #if os(iOS)
    private func generateIOSPDF(from reportData: ReportData, configuration: ReportConfiguration) async throws -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "BitMatch",
            kCGPDFContextTitle: "Master Transfer Report",
            kCGPDFContextSubject: "Production: \(configuration.production)",
            kCGPDFContextAuthor: configuration.company
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        return renderer.pdfData { context in
            try! self.renderPDFContentIOS(context: context, reportData: reportData, configuration: configuration, pageRect: pageRect)
        }
    }
    
    private func renderPDFContentIOS(
        context: UIGraphicsPDFRendererContext,
        reportData: ReportData,
        configuration: ReportConfiguration,
        pageRect: CGRect
    ) throws {
        context.beginPage()
        
        let contentRect = pageRect.insetBy(dx: configuration.margins.left, dy: configuration.margins.top)
        var yPosition: CGFloat = contentRect.minY
        
        // Render header
        yPosition = renderHeader(in: contentRect, at: yPosition, reportData: reportData, configuration: configuration)
        
        // Render summary
        yPosition = renderSummary(in: contentRect, at: yPosition, reportData: reportData, configuration: configuration)
        
        // Render production notes
        if !configuration.productionNotes.isEmpty {
            yPosition = renderProductionNotes(in: contentRect, at: yPosition, reportData: reportData, configuration: configuration)
        }
        
        // Render camera groups
        for cameraGroup in reportData.cameraGroups {
            // Check if we need a new page
            if yPosition > contentRect.maxY - 150 {
                context.beginPage()
                yPosition = contentRect.minY
            }
            
            yPosition = renderCameraGroup(cameraGroup, in: contentRect, at: yPosition, configuration: configuration)
        }
    }
    #endif
    
    // MARK: - PDF Content Rendering (Shared Logic)
    
    private func renderHeader(in rect: CGRect, at yPosition: CGFloat, reportData: ReportData, configuration: ReportConfiguration) -> CGFloat {
        var currentY = yPosition
        
        // Title
        let titleAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: 24, weight: .bold),
            NSAttributedString.Key.foregroundColor: platformColor(hex: configuration.primaryColor)
        ]
        
        let titleText = "MASTER TRANSFER REPORT"
        let titleSize = titleText.size(withAttributes: titleAttributes)
        titleText.draw(at: CGPoint(x: rect.midX - titleSize.width/2, y: currentY), withAttributes: titleAttributes)
        currentY += titleSize.height + 20
        
        // Metadata section
        let metadataAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: configuration.fontSize),
            NSAttributedString.Key.foregroundColor: platformColor(hex: "#000000")
        ]
        
        let metadata = [
            "Generated: \(reportData.generatedAt.formatted(date: .complete, time: .standard))",
            "Production: \(configuration.production)",
            "Client: \(configuration.client)",
            "Company: \(configuration.company)"
        ].filter { !$0.hasSuffix(": ") } // Remove empty fields
        
        for line in metadata {
            line.draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: metadataAttributes)
            currentY += configuration.fontSize + 4
        }
        
        return currentY + 20
    }
    
    private func renderSummary(in rect: CGRect, at yPosition: CGFloat, reportData: ReportData, configuration: ReportConfiguration) -> CGFloat {
        var currentY = yPosition
        
        // Summary section header
        let headerAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: 16, weight: .semibold),
            NSAttributedString.Key.foregroundColor: platformColor(hex: configuration.primaryColor)
        ]
        
        "SUMMARY".draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: headerAttributes)
        currentY += 20
        
        // Draw separator line
        #if os(macOS)
        NSColor(hex: configuration.secondaryColor).set()
        #else
        UIColor(hex: configuration.secondaryColor).set()
        #endif
        
        let linePath = platformBezierPath()
        linePath.move(to: CGPoint(x: rect.minX, y: currentY))
        linePath.line(to: CGPoint(x: rect.maxX, y: currentY))
        linePath.lineWidth = 1
        linePath.stroke()
        currentY += 15
        
        // Summary data
        let summaryAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: configuration.fontSize),
            NSAttributedString.Key.foregroundColor: platformColor(hex: "#000000")
        ]
        
        let summaryLines = [
            "Total Transfers: \(reportData.summary.totalTransfers)",
            "Total Files: \(reportData.summary.totalFiles.formatted())",
            "Total Size: \(reportData.summary.formattedSize)",
            "Verification Rate: \(String(format: "%.1f%%", reportData.summary.verificationRate * 100))"
        ]
        
        for line in summaryLines {
            line.draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: summaryAttributes)
            currentY += configuration.fontSize + 4
        }
        
        return currentY + 20
    }
    
    private func renderProductionNotes(in rect: CGRect, at yPosition: CGFloat, reportData: ReportData, configuration: ReportConfiguration) -> CGFloat {
        var currentY = yPosition
        
        // Production notes header
        let headerAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: 14, weight: .medium),
            NSAttributedString.Key.foregroundColor: platformColor(hex: configuration.primaryColor)
        ]
        
        "PRODUCTION NOTES".draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: headerAttributes)
        currentY += 18
        
        // Notes content
        let notesAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: configuration.fontSize),
            NSAttributedString.Key.foregroundColor: platformColor(hex: "#000000")
        ]
        
        let notesRect = CGRect(x: rect.minX, y: currentY, width: rect.width, height: 60)
        configuration.productionNotes.draw(in: notesRect, withAttributes: notesAttributes)
        
        return currentY + 80
    }
    
    private func renderCameraGroup(_ group: ReportData.CameraGroup, in rect: CGRect, at yPosition: CGFloat, configuration: ReportConfiguration) -> CGFloat {
        var currentY = yPosition
        
        // Camera group header
        let headerAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: 12, weight: .semibold),
            NSAttributedString.Key.foregroundColor: platformColor(hex: configuration.primaryColor)
        ]
        
        let groupTitle = "\(group.cameraName) (\(group.transfers.count) transfers)"
        groupTitle.draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: headerAttributes)
        currentY += 16
        
        // Transfer details
        let detailAttributes = [
            NSAttributedString.Key.font: platformFont(name: configuration.fontFamily, size: configuration.fontSize - 1),
            NSAttributedString.Key.foregroundColor: platformColor(hex: "#333333")
        ]
        
        for transfer in group.transfers {
            let transferSize = ByteCountFormatter.string(fromByteCount: transfer.totalSize, countStyle: .file)
            let verificationStatus = transfer.verified ? "✅ Verified" : "⚠️ Pending"
            
            let transferInfo = "  • \(transfer.sourcePath.components(separatedBy: "/").last ?? "Unknown") - \(transferSize) (\(transfer.fileCount) files) - \(verificationStatus)"
            transferInfo.draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: detailAttributes)
            currentY += configuration.fontSize + 2
            
            // Destination paths (indented)
            for destination in transfer.destinationPaths {
                let destInfo = "    → \(destination.components(separatedBy: "/").last ?? destination)"
                destInfo.draw(at: CGPoint(x: rect.minX, y: currentY), withAttributes: detailAttributes)
                currentY += configuration.fontSize + 1
            }
            
            currentY += 4 // Space between transfers
        }
        
        return currentY + 10
    }
    
    // MARK: - JSON Generation
    
    private func generateJSON(transfers: [TransferCard], configuration: ReportConfiguration) throws -> Data {
        struct MasterReportJSON: Codable {
            let generatedAt: Date
            let production: String
            let client: String
            let company: String
            let technician: String
            let productionNotes: String
            let totalSize: Int64
            let totalFiles: Int
            let totalTransfers: Int
            let verificationRate: Double
            let cameras: [CameraGroup]
            
            struct CameraGroup: Codable {
                let cameraName: String
                let totalTransfers: Int
                let totalFiles: Int
                let totalSize: Int64
                let transfers: [TransferSummary]
            }
            
            struct TransferSummary: Codable {
                let sourcePath: String
                let destinationPaths: [String]
                let fileCount: Int
                let totalSize: Int64
                let timestamp: Date
                let verified: Bool
            }
        }
        
        // Group by camera
        let cameraGroups = Dictionary(grouping: transfers) { $0.cameraName }
            .map { (cameraName, transfers) in
                MasterReportJSON.CameraGroup(
                    cameraName: cameraName,
                    totalTransfers: transfers.count,
                    totalFiles: transfers.reduce(0) { $0 + $1.fileCount },
                    totalSize: transfers.reduce(0) { $0 + $1.totalSize },
                    transfers: transfers.map { transfer in
                        MasterReportJSON.TransferSummary(
                            sourcePath: transfer.sourcePath,
                            destinationPaths: transfer.destinationPaths,
                            fileCount: transfer.fileCount,
                            totalSize: transfer.totalSize,
                            timestamp: transfer.timestamp,
                            verified: transfer.verified
                        )
                    }
                )
            }
        
        let reportJSON = MasterReportJSON(
            generatedAt: Date(),
            production: configuration.production,
            client: configuration.client,
            company: configuration.company,
            technician: configuration.technician,
            productionNotes: configuration.productionNotes,
            totalSize: transfers.reduce(0) { $0 + $1.totalSize },
            totalFiles: transfers.reduce(0) { $0 + $1.fileCount },
            totalTransfers: transfers.count,
            verificationRate: calculateVerificationRate(transfers: transfers),
            cameras: cameraGroups
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(reportJSON)
    }
    
    // MARK: - Helper Functions
    
    private func calculateVerificationRate(transfers: [TransferCard]) -> Double {
        guard !transfers.isEmpty else { return 0.0 }
        let verifiedCount = transfers.filter { $0.verified }.count
        return Double(verifiedCount) / Double(transfers.count)
    }
    
    // MARK: - Platform-Specific Helpers
    
    #if os(macOS)
    private func platformFont(name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
    
    private func platformColor(hex: String) -> NSColor {
        return NSColor(hex: hex)
    }
    
    private func platformBezierPath() -> NSBezierPath {
        return NSBezierPath()
    }
    #else
    private func platformFont(name: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
    
    private func platformColor(hex: String) -> UIColor {
        return UIColor(hex: hex)
    }
    
    private func platformBezierPath() -> UIBezierPath {
        return UIBezierPath()
    }
    #endif
}

// MARK: - Supporting Types

struct ReportData {
    let configuration: SharedReportGenerationService.ReportConfiguration
    let generatedAt: Date
    let summary: Summary
    let cameraGroups: [CameraGroup]
    let allTransfers: [TransferCard]
    
    struct Summary {
        let totalTransfers: Int
        let totalFiles: Int
        let totalSize: Int64
        let formattedSize: String
        let verificationRate: Double
    }
    
    struct CameraGroup {
        let cameraName: String
        let transfers: [TransferCard]
        let totalFiles: Int
        let totalSize: Int64
    }
}

struct MasterReportResult {
    let pdfData: Data
    let jsonData: Data
    let reportData: ReportData
    let generatedAt: Date
}

enum ReportGenerationError: LocalizedError {
    case pdfCreationFailed
    case jsonEncodingFailed
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed:
            return "Failed to create PDF report"
        case .jsonEncodingFailed:
            return "Failed to encode JSON report"
        case .invalidConfiguration:
            return "Invalid report configuration"
        }
    }
}

// MARK: - Color Extensions

#if os(macOS)
extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
#else
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
#endif