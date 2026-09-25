// ModularContentView.swift - Refactored modular iPad interface using components
import SwiftUI
import UIKit

struct ModularContentView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let navigationPresentation: AdaptiveNavigationPresentation
    @State private var showingSettings = false
    @State private var showingTransfers = false
    @State private var showingVolumeSelector = false
    @State private var showCancelToast = false
    
    // Outcome logic lives on the coordinator so phone, pad, and Mac share
    // one definition of which states keep results visible.
    
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
                    ToastView(
                        icon: "xmark.circle",
                        message: coordinator.currentMode == .compareFolders ? "Compare cancelled" : "Transfer cancelled",
                        tint: .red
                    )
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
        .sheet(isPresented: $showingTransfers) {
            TransferLibraryView(coordinator: coordinator, journal: coordinator.transferJournal)
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
            HeaderSectionView(showingSettings: $showingSettings, showingTransfers: $showingTransfers)
            if coordinator.transferJournal.records.contains(where: { $0.state == .interrupted }) {
                Button("Interrupted transfer — review in Transfers") { showingTransfers = true }
                    .font(.callout).foregroundStyle(.orange).padding(.horizontal)
            }
            
            // Three-state architecture using components. Compare shows its own
            // progress and outcome inside CompareScreen, so it stays on the
            // mode view instead of the transfer progress/completion screens.
            if coordinator.currentMode == .compareFolders {
                IdleStateView(coordinator: coordinator, navigationPresentation: navigationPresentation)
            } else if coordinator.isOperationInProgress {
                // OPERATION STATE: Show progress interface
                OperationProgressView(coordinator: coordinator)
                    .onAppear {
                        SharedLogger.debug("UI switched to OPERATION view")
                    }
            } else if coordinator.showsOutcomeSummary {
                // COMPLETION STATE: Show transfer summary
                ScrollView { CompletionSummaryView(coordinator: coordinator) }
                    .onAppear {
                        SharedLogger.debug("UI switched to COMPLETION view")
                    }
            } else {
                // IDLE STATE: Show file selection interface
                IdleStateView(coordinator: coordinator, navigationPresentation: navigationPresentation)
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
    @Binding var showingTransfers: Bool
    
    var body: some View {
        HStack {
            Button("Transfers", systemImage: "clock.arrow.circlepath") { showingTransfers = true }
                .frame(minHeight: 44)
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Idle State View Component

struct IdleStateView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let navigationPresentation: AdaptiveNavigationPresentation
    
    var body: some View {
        Group {
            if navigationPresentation == .sidebar {
                HStack(alignment: .top, spacing: 0) {
                    AdaptiveModeNavigation(coordinator: coordinator, presentation: .sidebar)
                    Divider().overlay(Color.white.opacity(0.09))
                    modeContent
                }
            } else {
                VStack(spacing: 0) {
                    AdaptiveModeNavigation(coordinator: coordinator, presentation: .toolbar)
                    modeContent
                }
            }
        }
    }

    private var modeContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch coordinator.currentMode {
                case .copyAndVerify:
                    CopyAndVerifyView(coordinator: coordinator)
                        .frame(maxWidth: 1_100)
                case .compareFolders:
                    CompareFoldersView(coordinator: coordinator)
                        .frame(maxWidth: 1_100)
                        .padding(.horizontal, 20)
                case .masterReport:
                    MasterReportView(coordinator: coordinator)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Compare Folders (adapter over the shared CompareScreen)

/// Builds the shared `ComparePresentation` from `SharedAppCoordinator`.
/// Readiness, progress and the outcome all render inside `CompareScreen`;
/// Compare never routes to the transfer progress or completion screens.
struct CompareFoldersView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var advancedExpanded = false

    static func presentation(for coordinator: SharedAppCoordinator) -> ComparePresentation {
        ComparePresentation.make(
            left: slot(url: coordinator.leftURL, info: coordinator.leftFolderInfo, coordinator: coordinator),
            right: slot(url: coordinator.rightURL, info: coordinator.rightFolderInfo, coordinator: coordinator),
            mode: coordinator.verificationMode,
            isRunning: coordinator.isOperationInProgress,
            progress: coordinator.progress.map {
                CompareProgressPresentation(
                    fraction: $0.overallProgress,
                    filesProcessed: $0.filesProcessed,
                    totalFiles: $0.totalFiles,
                    currentFile: $0.currentFile
                )
            },
            stats: coordinator.lastCompareStats,
            end: coordinator.lastCompareEnd
        )
    }

    private static func slot(
        url: URL?,
        info: EnhancedFolderInfo?,
        coordinator: SharedAppCoordinator
    ) -> CompareFolderSlot {
        CompareFolderSlot.make(
            url: url,
            infoURL: info?.url,
            fileCount: info?.fileCount,
            totalSize: info?.totalSize,
            // A scan that has not started yet (no entry) counts as loading, so
            // Compare cannot enable in the moment between picking and scanning.
            isFetching: url.map { coordinator.folderInfoLoadingState[$0] != false } ?? false
        )
    }

    var body: some View {
        CompareScreen(
            presentation: Self.presentation(for: coordinator),
            verificationMode: $coordinator.verificationMode,
            advancedExpanded: $advancedExpanded,
            actions: CompareActions(
                pickLeft: { Task { await coordinator.selectLeftFolder() } },
                pickRight: { Task { await coordinator.selectRightFolder() } },
                clearLeft: { coordinator.leftURL = nil },
                clearRight: { coordinator.rightURL = nil },
                dropLeft: nil,
                dropRight: nil,
                compare: { Task { await coordinator.compareFolders() } },
                cancel: { coordinator.cancelOperation() }
            )
        )
    }
}

// MARK: - Master Report View Component

struct MasterReportView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var isScanning = false
    @State private var discoveredTransfers: [TransferCard] = []
    @State private var selectedTransfers = Set<UUID>()
    @State private var volumeScanTask: Task<Void, Never>?
    @State private var activeVolumeScanID: UUID?
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
        volumeScanTask?.cancel()
        let scanID = UUID()
        activeVolumeScanID = scanID
        volumeScanTask = Task {
            isScanning = true
            showingVolumeSelector = false

            // Use real IOSDriverScanner to discover transfers
            let volumeURL = URL(fileURLWithPath: volume.path)
            let transfers = await IOSDriverScanner.scanForBitMatchReports(at: volumeURL)

            // A newer volume scan supersedes this one.
            guard activeVolumeScanID == scanID else { return }
            discoveredTransfers = transfers

            // Select all discovered transfers by default
            selectedTransfers = Set(transfers.map { $0.id })

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
        MobileWorkflowHeader(
            title: "Master report",
            detail: "Find completed transfers and collect their reports.",
            symbol: "doc.text.magnifyingglass",
            tint: .blue
        )
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
                    Text(coordinator.verificationMode == .standard ? "Verified copy · SHA-256" : coordinator.verificationMode.rawValue)
                    DisclosureGroup("Advanced verification") {
                        Picker("Verification", selection: $coordinator.verificationMode) {
                            ForEach(VerificationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .onChange(of: coordinator.verificationMode) { _, _ in coordinator.saveVerificationMode() }
                        Text(coordinator.verificationMode.description).font(.footnote)
                        Toggle("ASC MHL handoff record", isOn: $coordinator.generateASCMHL)
                            .disabled(coordinator.verificationMode == .quick)
                        Text("Creates an interoperable checksum record for verified copies.").font(.footnote)
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

                Section("Off-site destinations") {
                    RemoteDestinationSettingsSection(coordinator: coordinator)
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

private struct RemoteDestinationSettingsSection: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var isAddingDestination = false
    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var root = ""
    @State private var error: String?

    var body: some View {
        if coordinator.photographerJobViewModel.remoteProfiles.isEmpty {
            Text("Save an SFTP destination once, then choose it from any project. Uploads remain a Mac task.")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else {
            ForEach(coordinator.photographerJobViewModel.remoteProfiles) { profile in
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                    Text("\(profile.username)@\(profile.host):\(profile.port) · \(profile.root.description)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        coordinator.photographerJobViewModel.deleteRemoteProfile(id: profile.id)
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }

        Button { isAddingDestination = true } label: {
            Label("Add destination", systemImage: "plus")
        }
        .sheet(isPresented: $isAddingDestination) {
            NavigationStack {
                Form {
                    Section("Destination") {
                        TextField("Name", text: $name)
                        TextField("Host", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Remote folder", text: $root).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section {
                        Text("BitMatch stores only destination metadata here. Your Mac uses its SSH agent and verifies the host before uploading.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    if let error { Section { Text(error).foregroundColor(.red) } }
                }
                .navigationTitle("New destination")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: reset) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func save() {
        do {
            let components = root.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            let profile = RemoteDestinationProfile(
                id: UUID(),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: 22,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                root: try RemoteRelativePath(components: components),
                verificationMode: .sha256
            )
            coordinator.photographerJobViewModel.saveRemoteProfile(profile)
            if let message = coordinator.photographerJobViewModel.lastError { error = message }
            else { reset() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reset() {
        name = ""; host = ""; username = ""; root = ""; error = nil; isAddingDestination = false
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
