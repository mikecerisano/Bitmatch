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
    // Owned scan task + generation: starting a new scan cancels the
    // previous enumeration, and stale results never overwrite fresh ones.
    @State private var scanTask: Task<Void, Never>?
    @State private var activeScanID: UUID?
    
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
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        scanningDrive = true

        scanTask = Task {
            let transfers = await DriveScanner.scanForBitMatchReports(at: url)

            await MainActor.run {
                // A newer scan (or a cleared view) supersedes this one.
                guard self.activeScanID == scanID else { return }
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
            let selectedTransfersArray = foundTransfers.filter { selectedTransfers.contains($0.id) }
            let configuration = SharedReportGenerationService.ReportConfiguration.make(
                from: coordinator.reportSettings,
                productionNotes: productionNotes
            )
            Task {
                do {
                    try await writeMasterReport(transfers: selectedTransfersArray, configuration: configuration, to: url)
                    await MainActor.run {
                        self.isGeneratingReport = false
                        self.showSuccessAlert(at: url)
                    }
                } catch {
                    AppLogger.error("Failed to generate report: \(error)", category: .general)
                    await MainActor.run {
                        self.isGeneratingReport = false
                        self.showErrorAlert(error: error)
                    }
                }
            }
        } else {
            isGeneratingReport = false
        }
    }
    
    // MARK: - Report Generation
    
    /// Writes the PDF and its sibling JSON. Throws on any failure, so the
    /// success alert only appears after both files are written.
    private func writeMasterReport(
        transfers: [TransferCard],
        configuration: SharedReportGenerationService.ReportConfiguration,
        to url: URL
    ) async throws {
        let reportService = SharedReportGenerationService()
        let result = try await reportService.generateMasterReport(
            transfers: transfers,
            configuration: configuration
        )
        try result.pdfData.write(to: url)
        try result.jsonData.write(to: url.deletingPathExtension().appendingPathExtension("json"))
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