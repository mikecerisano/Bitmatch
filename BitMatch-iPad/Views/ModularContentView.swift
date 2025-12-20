// ModularContentView.swift - Refactored modular iPad interface using components
import SwiftUI
import UIKit

struct ModularContentView: View {
    @StateObject private var coordinator = SharedAppCoordinator()
    @State private var showingSettings = false
    @State private var showingVolumeSelector = false
    @State private var showCancelToast = false
    
    // Simplified completion logic
    private var showCompletionSummary: Bool {
        if case .completed = coordinator.operationState {
            return true
        }
        return false
    }
    
    var body: some View {
        ZStack {
            // Background gradient (matching original)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.05),
                    Color(red: 0.1, green: 0.1, blue: 0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Main content area
            mainContentArea
            if showCancelToast {
                VStack {
                    ToastView(icon: "xmark.circle", message: "User cancelled transfer", tint: .red)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: coordinator.operationState) { oldValue, newValue in
            // Handle transfer completion logic
            if case .completed = newValue {
                SharedLogger.info("Transfer completed, showing summary")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingVolumeSelector) {
            VolumeSelector(coordinator: coordinator, showingVolumeSelector: $showingVolumeSelector)
        }
        .onReceive(NotificationCenter.default.publisher(for: .operationCancelledByUser)) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showCancelToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showCancelToast = false
                }
            }
        }
    }
}

// MARK: - Main Content Area

extension ModularContentView {
    @ViewBuilder
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            // Header with gear icon (always visible)  
            HeaderSectionView(showingSettings: $showingSettings)
            
            // Three-state architecture using components
            if coordinator.isOperationInProgress {
                // OPERATION STATE: Show progress interface
                OperationProgressView(coordinator: coordinator)
                    .onAppear {
                        SharedLogger.debug("UI switched to OPERATION view")
                    }
            } else if showCompletionSummary {
                // COMPLETION STATE: Show transfer summary
                CompletionSummaryView(coordinator: coordinator)
                    .onAppear {
                        SharedLogger.debug("UI switched to COMPLETION view")
                    }
            } else {
                // IDLE STATE: Show file selection interface
                IdleStateView(coordinator: coordinator)
                    .onAppear {
                        SharedLogger.debug("UI switched to IDLE view")
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Header Section Component

struct HeaderSectionView: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        HStack {
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Idle State View Component

struct IdleStateView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 0) {
            // Top tabs navigation
            HeaderTabsView(coordinator: coordinator)
            
            // Main scrollable content - switches based on selected mode
            ScrollView {
                VStack(spacing: 24) {
                    // Content switches based on current mode using components
                    switch coordinator.currentMode {
                    case .copyAndVerify:
                        CopyAndVerifyView(coordinator: coordinator)
                    case .compareFolders:
                        CompareFoldersView(coordinator: coordinator)
                    case .masterReport:
                        MasterReportView(coordinator: coordinator)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Compare Folders View Component

struct CompareFoldersView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var showingLeftPicker = false
    @State private var showingRightPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header section
            CompareFoldersHeaderView()
            
            if coordinator.isOperationInProgress {
                // Show comparison progress
                ComparisonProgressView(coordinator: coordinator)
            } else {
                // Show folder selection interface
                VStack(spacing: 20) {
                    // Side-by-side folder selection
                    HStack(spacing: 16) {
                        FolderSelectionCard(
                            title: "LEFT FOLDER",
                            subtitle: "Source of truth",
                            url: coordinator.leftURL,
                            folderInfo: coordinator.leftFolderInfo?.asFolderInfo,
                            isLoading: coordinator.leftURL.map { coordinator.isFolderInfoLoading(for: $0) } ?? false,
                            color: .blue,
                            onSelect: { showingLeftPicker = true },
                            onClear: { coordinator.leftURL = nil }
                        )
                        
                        FolderSelectionCard(
                            title: "RIGHT FOLDER",
                            subtitle: "To compare",
                            url: coordinator.rightURL,
                            folderInfo: coordinator.rightFolderInfo?.asFolderInfo,
                            isLoading: coordinator.rightURL.map { coordinator.isFolderInfoLoading(for: $0) } ?? false,
                            color: .green,
                            onSelect: { showingRightPicker = true },
                            onClear: { coordinator.rightURL = nil }
                        )
                    }
                    
                    // Comparison controls
                    if coordinator.leftURL != nil && coordinator.rightURL != nil {
                        ComparisonControlsView(coordinator: coordinator)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingLeftPicker) {
            FolderPicker(title: "Select Left Folder") { url in
                coordinator.leftURL = url
            }
        }
        .sheet(isPresented: $showingRightPicker) {
            FolderPicker(title: "Select Right Folder") { url in
                coordinator.rightURL = url
            }
        }
    }
}

// MARK: - Compare Folders Sub-Components

struct CompareFoldersHeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                
                Text("COMPARE FOLDERS")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text("Compare two folders to identify differences and verify integrity")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
        }
    }
}

struct FolderSelectionCard: View {
    let title: String
    let subtitle: String
    let url: URL?
    let folderInfo: FolderInfo?
    let isLoading: Bool
    let color: Color
    let onSelect: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Content area
            Button {
                if url != nil {
                    // Already selected - could show details or clear
                } else {
                    onSelect()
                }
            } label: {
                VStack(spacing: 12) {
                    if let url = url, let info = folderInfo {
                        // Show folder details
                        VStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 32))
                                .foregroundColor(color)
                            
                            Text(url.lastPathComponent)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            VStack(spacing: 4) {
                                HStack {
                                    Text("\(info.formattedFileCount) files")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Spacer()
                                    
                                    Text(info.formattedSize)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Text(url.path)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else if isLoading {
                        // Show loading state
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: color))
                                .scaleEffect(1.2)
                            
                            Text("Analyzing folder...")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Show selection prompt
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(color.opacity(0.6))
                            
                            Text("Select Folder")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("Tap to choose")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.vertical, 20)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(url != nil ? color.opacity(0.1) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(url != nil ? color.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Clear button if folder is selected
            if url != nil {
                Button {
                    onClear()
                } label: {
                    Text("Clear Selection")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(color)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ComparisonControlsView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 16) {
            // Comparison options
            VStack(spacing: 12) {
                Text("COMPARISON OPTIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                VStack(spacing: 8) {
                    Toggle("Include file sizes", isOn: .constant(true))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    
                    Toggle("Check modification dates", isOn: .constant(true))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    
                    Toggle("Verify checksums", isOn: .constant(false))
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
            
            // Start comparison button
            Button {
                Task {
                    await coordinator.compareFolders()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Compare Folders")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct ComparisonProgressView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Comparing Folders...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            if let progress = coordinator.progress {
                VStack(spacing: 12) {
                    ProgressView(value: progress.overallProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                        .scaleEffect(y: 2.0)
                    
                    HStack {
                        Text("Files analyzed: \(progress.filesProcessed)/\(progress.totalFiles)")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text("\(Int(progress.overallProgress * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                )
            }
            
            Button {
                coordinator.cancelOperation()
            } label: {
                Text("Cancel Comparison")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

struct FolderPicker: View {
    let title: String
    let onSelection: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("iOS folder picker would be presented here")
                    .padding()
                
                Button("Cancel") {
                    dismiss()
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Master Report View Component

struct MasterReportView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var isScanning = false
    @State private var discoveredTransfers: [TransferCard] = []
    @State private var selectedTransfers = Set<UUID>()
    @State private var availableVolumes: [ReportVolumeInfo] = []
    @State private var showingVolumeSelector = false
    @State private var reportConfiguration = SharedReportGenerationService.ReportConfiguration.default()
    @State private var showingReportSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header section
            MasterReportHeaderView(
                coordinator: coordinator,
                isScanning: $isScanning,
                showingVolumeSelector: $showingVolumeSelector
            )
            
            // Main content area
            if isScanning {
                MasterReportScanningView()
            } else if discoveredTransfers.isEmpty {
                MasterReportEmptyStateView(onStartScan: startVolumeScan)
            } else {
                MasterReportTransferListView(
                    transfers: discoveredTransfers,
                    selectedTransfers: $selectedTransfers,
                    reportConfiguration: $reportConfiguration,
                    showingReportSettings: $showingReportSettings,
                    onGenerateReport: generateMasterReport
                )
            }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingVolumeSelector) {
            VolumeSelectionSheet(
                availableVolumes: availableVolumes,
                onVolumeSelected: scanVolume
            )
        }
        .sheet(isPresented: $showingReportSettings) {
            ReportConfigurationSheet(
                configuration: $reportConfiguration
            )
        }
    }
    
    // MARK: - Actions
    
    private func startVolumeScan() {
        Task {
            isScanning = true
            await loadAvailableVolumes()
            isScanning = false
            showingVolumeSelector = true
        }
    }
    
    private func loadAvailableVolumes() async {
        let volumes = IOSDriverScanner.getAvailableVolumes()
        availableVolumes = volumes.map { volume in
            let driveType: DriveType
            switch volume.volumeType {
            case .internal:
                driveType = .internalDrive
            case .external:
                driveType = .externalDrive
            case .removable:
                driveType = .cameraCard
            case .network:
                driveType = .networkDrive
            }
            
            return ReportVolumeInfo(
                name: volume.name,
                path: volume.path,
                type: driveType
            )
        }
    }
    
    private func scanVolume(_ volume: ReportVolumeInfo) {
        Task {
            isScanning = true
            showingVolumeSelector = false
            
            // Use real IOSDriverScanner to discover transfers
            let volumeURL = URL(fileURLWithPath: volume.path)
            discoveredTransfers = await IOSDriverScanner.scanForBitMatchReports(at: volumeURL)
            
            // Select all discovered transfers by default
            selectedTransfers = Set(discoveredTransfers.map { $0.id })
            
            isScanning = false
        }
    }
    
    private func generateMasterReport() {
        let selectedCards = discoveredTransfers.filter { selectedTransfers.contains($0.id) }
        
        Task {
            do {
                let reportService = SharedReportGenerationService()
                let result = try await reportService.generateMasterReport(
                    transfers: selectedCards,
                    configuration: reportConfiguration
                )
                
                // Present share sheet for PDF and JSON files
                await presentShareSheet(for: result)
                
            } catch {
                await coordinator.showError(error)
            }
        }
    }
    
    @MainActor
    private func presentShareSheet(for result: MasterReportResult) async {
        // Create temporary URLs for sharing
        let tempDirectory = FileManager.default.temporaryDirectory
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: result.generatedAt)
        
        let pdfURL = tempDirectory.appendingPathComponent("Master_Report_\(timestamp).pdf")
        let jsonURL = tempDirectory.appendingPathComponent("Master_Report_\(timestamp).json")
        
        do {
            // Write files to temporary directory
            try result.pdfData.write(to: pdfURL)
            try result.jsonData.write(to: jsonURL)
            
            // Present share sheet with both files
            await presentNativeShareSheet(items: [pdfURL, jsonURL])
            
        } catch {
            await coordinator.showError(error)
        }
    }
    
    @MainActor
    private func presentNativeShareSheet(items: [Any]) async {
        // Get the root view controller for presenting the share sheet
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            await coordinator.showAlert(
                title: "Share Error",
                message: "Could not present share sheet"
            )
            return
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(
                x: rootViewController.view.bounds.midX,
                y: rootViewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        
        rootViewController.present(activityViewController, animated: true)
        
        await coordinator.showAlert(
            title: "Report Generated",
            message: "Master report generated successfully with \(discoveredTransfers.filter { selectedTransfers.contains($0.id) }.count) transfers."
        )
    }
}

// MARK: - Master Report Sub-Components

struct MasterReportHeaderView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var isScanning: Bool
    @Binding var showingVolumeSelector: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                Text("MASTER REPORT")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text("Scan volumes to discover completed transfers and generate comprehensive reports")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
        }
    }
}

struct MasterReportEmptyStateView: View {
    let onStartScan: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No Transfers Found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Scan available volumes to discover completed transfers")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button {
                onStartScan()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Scan Volumes")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 40)
    }
}

struct MasterReportScanningView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.2)
            
            Text("Scanning for Transfers...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Text("Searching volumes for completed transfers")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 60)
    }
}

struct MasterReportTransferListView: View {
    let transfers: [TransferCard]
    @Binding var selectedTransfers: Set<UUID>
    @Binding var reportConfiguration: SharedReportGenerationService.ReportConfiguration
    @Binding var showingReportSettings: Bool
    let onGenerateReport: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Transfer selection header
            HStack {
                Text("DISCOVERED TRANSFERS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Spacer()
                
                Text("\(selectedTransfers.count)/\(transfers.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Transfer list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(transfers) { transfer in
                        TransferSelectionCard(
                            transfer: transfer,
                            isSelected: selectedTransfers.contains(transfer.id),
                            onToggle: {
                                if selectedTransfers.contains(transfer.id) {
                                    selectedTransfers.remove(transfer.id)
                                } else {
                                    selectedTransfers.insert(transfer.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 300)
            
            // Generation controls
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Report settings button
                    Button {
                        showingReportSettings = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                                .font(.system(size: 12))
                            Text("Settings")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Select all/none toggle
                    Button {
                        if selectedTransfers.count == transfers.count {
                            selectedTransfers.removeAll()
                        } else {
                            selectedTransfers = Set(transfers.map { $0.id })
                        }
                    } label: {
                        Text(selectedTransfers.count == transfers.count ? "Deselect All" : "Select All")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                // Generate report button
                Button {
                    onGenerateReport()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Generate Master Report")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedTransfers.isEmpty ? Color.gray : Color.blue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedTransfers.isEmpty)
            }
        }
    }
}

struct TransferSelectionCard: View {
    let transfer: TransferCard
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .blue : .white.opacity(0.3))
                
                // Transfer info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transfer.cameraName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(transfer.formattedSize)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Text(transfer.sourcePath.components(separatedBy: "/").last ?? "Unknown Path")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    HStack {
                        Text("\(transfer.fileCount.formatted()) files")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: transfer.verified ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(transfer.verified ? .green : .orange)
                            
                            Text(transfer.verified ? "Verified" : "Unverified")
                                .font(.system(size: 11))
                                .foregroundColor(transfer.verified ? .green : .orange)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Sheet Components

struct VolumeSelectionSheet: View {
    let availableVolumes: [ReportVolumeInfo]
    let onVolumeSelected: (ReportVolumeInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Select Volume to Scan")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(.top)
                
                if availableVolumes.isEmpty {
                    Text("No volumes found")
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(availableVolumes, id: \.path) { volume in
                            Button {
                                onVolumeSelected(volume)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: volume.type.systemImage)
                                        .font(.system(size: 20))
                                        .foregroundColor(volume.type.color)
                                    
                                    VStack(alignment: .leading) {
                                        Text(volume.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Text(volume.path)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ReportConfigurationSheet: View {
    @Binding var configuration: SharedReportGenerationService.ReportConfiguration
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Production Details") {
                    TextField("Production Name", text: $configuration.production)
                    TextField("Client", text: $configuration.client)
                    TextField("Company", text: $configuration.company)
                    TextField("Technician", text: $configuration.technician)
                }
                
                Section("Notes") {
                    TextField("Production Notes", text: $configuration.productionNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Options") {
                    Toggle("Include Thumbnails", isOn: $configuration.includeThumbnails)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .foregroundColor(.white)
            .navigationTitle("Report Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Supporting Types

struct ReportVolumeInfo {
    let name: String
    let path: String
    let type: DriveType
}

extension ReportVolumeInfo {
    var systemImage: String { type.systemImage }
    var color: Color { type.color }
}

// MARK: - Settings Sheet Component (Placeholder)

struct SettingsSheetView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Verification") {
                    Picker("Mode", selection: $coordinator.verificationMode) {
                        ForEach(VerificationMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue)
                        }
                    }
                }

                Section("Reports") {
                    Toggle("Generate PDF & JSON reports", isOn: $coordinator.reportSettings.makeReport)
                    Button(role: .destructive) {
                        clearReportInfo()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Report Info")
                        }
                    }
                }

                #if os(iOS)
                Section("Background Behavior") {
                    Toggle("Prevent Auto-Lock During Transfer", isOn: Binding(
                        get: { (UserDefaults.standard.object(forKey: "PreventAutoLockDuringTransfer") as? Bool) ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "PreventAutoLockDuringTransfer") }
                    ))
                    Toggle("Dim Screen While Awake", isOn: Binding(
                        get: { (UserDefaults.standard.object(forKey: "DimScreenWhileAwake") as? Bool) ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "DimScreenWhileAwake") }
                    ))
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .foregroundColor(.white)
            .navigationBarTitle("Settings", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func clearReportInfo() {
        var prefs = coordinator.reportSettings
        prefs.clientName = ""
        prefs.projectName = ""
        prefs.production = ""
        prefs.company = ""
        prefs.notes = ""
        coordinator.reportSettings = prefs
    }
}

// MARK: - Volume Selector Component (Placeholder)

struct VolumeSelector: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var showingVolumeSelector: Bool
    
    var body: some View {
        VStack {
            Text("Volume Selector")
                .font(.largeTitle)
                .foregroundColor(.white)
            
            Spacer()
            
            Text("Volume selection functionality would go here")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
            
            Button("Close") {
                showingVolumeSelector = false
            }
            .foregroundColor(.blue)
            .padding()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
