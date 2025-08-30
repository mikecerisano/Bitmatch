// Views/MasterReportView.swift - Refactored to use focused components
import SwiftUI
import AppKit

struct MasterReportView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var scanningDrive = false
    @State private var foundTransfers: [TransferCard] = []
    @State private var selectedTransfers = Set<UUID>()
    @State private var productionNotes = ""
    @State private var isGeneratingReport = false
    
    var body: some View {
        VStack(spacing: 20) {
            if scanningDrive {
                MasterReportScanningView(isScanning: scanningDrive)
            } else if foundTransfers.isEmpty {
                MasterReportEmptyState(onScanDrive: selectDriveAndScan)
            } else {
                MasterReportTransfersView(
                    foundTransfers: foundTransfers,
                    selectedTransfers: $selectedTransfers,
                    productionNotes: $productionNotes,
                    onGenerateReport: generateMasterReport
                )
            }
            
            Spacer() // Push content up but allow proper spacing from bottom
        }
        .padding(.top, 16) // Add top padding to match bottom padding
        .padding(.bottom, 16) // Ensure consistent bottom padding
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scanningDrive)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: foundTransfers.count)
    }
    
    // MARK: - Actions
    
    private func selectDriveAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Select Drive to Scan"
        
        if panel.runModal() == .OK, let url = panel.url {
            scanningDrive = true
            scanDrive(at: url)
        }
    }
    
    private func scanDrive(at url: URL) {
        scanningDrive = true
        
        Task {
            let transfers = await DriveScanner.scanForBitMatchReports(at: url)
            
            await MainActor.run {
                self.foundTransfers = transfers
                self.scanningDrive = false
                
                // Auto-select all by default
                self.selectedTransfers = Set(transfers.map { $0.id })
            }
        }
    }
    
    private func generateMasterReport() {
        guard !selectedTransfers.isEmpty else { return }
        
        isGeneratingReport = true
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MasterReport_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-"))"
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let selectedTransfersArray = foundTransfers.filter { selectedTransfers.contains($0.id) }
                
                // Generate PDF report
                await generateMasterReportPDF(transfers: selectedTransfersArray, to: url)
                
                // Save JSON metadata
                let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
                saveMasterReportJSON(transfers: selectedTransfersArray, to: jsonURL)
                
                await MainActor.run {
                    self.isGeneratingReport = false
                    self.showSuccessAlert(at: url)
                }
            }
        } else {
            isGeneratingReport = false
        }
    }
    
    // MARK: - Report Generation
    
    private func generateMasterReportPDF(transfers: [TransferCard], to url: URL) async {
        // This would contain the PDF generation logic
        // For now, create a placeholder implementation
        let pdfData = "Master Report PDF Generation Placeholder".data(using: .utf8) ?? Data()
        try? pdfData.write(to: url)
    }
    
    private func saveMasterReportJSON(transfers: [TransferCard], to url: URL) {
        struct MasterReportJSON: Codable {
            let generatedAt: Date
            let production: String
            let client: String
            let company: String
            let productionNotes: String
            let totalSize: Int64
            let totalFiles: Int
            let totalRolls: Int
            let cameras: [CameraGroup]
            
            struct CameraGroup: Codable {
                let cameraName: String
                let transfers: [TransferInfo]
            }
            
            struct TransferInfo: Codable {
                let sourcePath: String
                let destinationPaths: [String]
                let totalSize: Int64
                let fileCount: Int
                let timestamp: Date
                let verified: Bool
            }
        }
        
        // Group transfers by camera
        let grouped = Dictionary(grouping: transfers) { $0.cameraName }
        let cameraGroups = grouped.map { camera, transfers in
            MasterReportJSON.CameraGroup(
                cameraName: camera,
                transfers: transfers.map { transfer in
                    MasterReportJSON.TransferInfo(
                        sourcePath: transfer.sourcePath,
                        destinationPaths: transfer.destinationPaths,
                        totalSize: transfer.totalSize,
                        fileCount: transfer.fileCount,
                        timestamp: transfer.timestamp,
                        verified: transfer.verified
                    )
                }
            )
        }
        
        let report = MasterReportJSON(
            generatedAt: Date(),
            production: coordinator.settingsViewModel.prefs.production,
            client: coordinator.settingsViewModel.prefs.client,
            company: coordinator.settingsViewModel.prefs.company,
            productionNotes: productionNotes,
            totalSize: transfers.reduce(0) { $0 + $1.totalSize },
            totalFiles: transfers.reduce(0) { $0 + $1.fileCount },
            totalRolls: transfers.reduce(0) { $0 + $1.rolls },
            cameras: cameraGroups
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(report)
            try data.write(to: url)
        } catch {
            print("Failed to save JSON report: \(error)")
        }
    }
    
    // MARK: - Alert Helpers
    
    private func showSuccessAlert(at url: URL) {
        let alert = NSAlert()
        alert.messageText = "Master Report Generated"
        alert.informativeText = "Report saved successfully to:\n\(url.lastPathComponent)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }
    
    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Generate Report"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}