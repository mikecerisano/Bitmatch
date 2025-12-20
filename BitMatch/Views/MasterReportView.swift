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
        do {
            let reportService = SharedReportGenerationService()
            let configuration = SharedReportGenerationService.ReportConfiguration(
                production: coordinator.settingsViewModel.prefs.production,
                client: coordinator.settingsViewModel.prefs.clientName,
                company: coordinator.settingsViewModel.prefs.company,
                technician: coordinator.settingsViewModel.prefs.notes,
                productionNotes: productionNotes,
                includeThumbnails: false,
                logoPath: nil,
                primaryColor: "#007AFF",
                secondaryColor: "#8E8E93",
                fontFamily: "Helvetica",
                fontSize: 10,
                margins: .standard
            )
            
            let result = try await reportService.generateMasterReport(
                transfers: transfers,
                configuration: configuration
            )
            
            // Save PDF
            try result.pdfData.write(to: url)
            
            // Save JSON
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            try result.jsonData.write(to: jsonURL)
            
        } catch {
            AppLogger.error("Failed to generate report: \(error)", category: .general)
            await MainActor.run {
                showErrorAlert(error: error)
            }
        }
    }
    
    private func saveMasterReportJSON(transfers: [TransferCard], to url: URL) {
        // This method is now handled by SharedReportGenerationService
        // Left empty for compatibility, but generateMasterReportPDF now handles both PDF and JSON
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