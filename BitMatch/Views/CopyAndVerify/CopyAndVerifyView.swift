// Views/CopyAndVerify/CopyAndVerifyView.swift
import SwiftUI
import AppKit

struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var showReportSettings: Bool
    @Binding var cameraLabelExpanded: Bool
    @Binding var verificationModeExpanded: Bool
    
    // Convenience accessors
    private var fileSelection: FileSelectionViewModel { coordinator.fileSelectionViewModel }
    private var progress: ProgressViewModel { coordinator.progressViewModel }
    private var cameraLabel: CameraLabelViewModel { coordinator.cameraLabelViewModel }
    private var settings: SettingsViewModel { coordinator.settingsViewModel }
    
    private var currentFileName: String? {
        if coordinator.isOperationInProgress,
           let lastPath = coordinator.results.last?.path {
            return URL(fileURLWithPath: lastPath).lastPathComponent
        }
        return nil
    }
    
    private var speed: String? {
        // Prefer average data rate
        progress.formattedAverageDataRate ?? progress.formattedSpeed
    }
    
    private var timeRemaining: String? {
        progress.formattedTimeRemaining
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if coordinator.isOperationInProgress {
                // Compact transfer interface during operations
                compactOperationView
            } else {
                // Full-size interface when idle
                expandedIdleView
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: coordinator.isOperationInProgress)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: coordinator.completionState)
        .alert("Invalid Destination", isPresented: Binding(
            get: { coordinator.operationViewModel.showError },
            set: { coordinator.operationViewModel.showError = $0 }
        )) {
            Button("OK") {
                coordinator.operationViewModel.errorMessage = nil
            }
        } message: {
            Text(coordinator.operationViewModel.errorMessage ?? "An error occurred")
        }
        .onAppear {
            updateModeEstimates()
        }
        .onChange(of: fileSelection.sourceURL) { _, _ in
            updateModeEstimates()
        }
        .onChange(of: fileSelection.destinationURLs) { _, _ in
            updateModeEstimates()
        }
        .onChange(of: fileSelection.sourceFolderInfo?.totalSize) { _, _ in
            updateModeEstimates()
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var compactOperationView: some View {
        VStack(spacing: 0) {
            // Compact header showing source → destinations
            compactHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.3))
            
            // Main transfer queue
            TransferQueueView(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .move(edge: .top)).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .move(edge: .bottom)).combined(with: .opacity)
                ))
        }
    }
    
    @ViewBuilder
    private var expandedIdleView: some View {
        VStack(spacing: 0) {
            HorizontalFlowView(coordinator: coordinator)
                .frame(maxHeight: .infinity)
            
            // Bottom control panel (only show when not verifying)
            controlPanel
                .padding(.top, 12)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    @ViewBuilder
    private var compactHeader: some View {
        HStack(spacing: 12) {
            // Source info
            if let sourceURL = fileSelection.sourceURL {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    Text(sourceURL.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            // Destinations count
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                
                Text("\(fileSelection.destinationURLs.count) destinations")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Overall progress (overall, not per-file)
            if let speed = speed {
                HStack(spacing: 4) {
                    Text(speed)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    if let filesLeft = progress.formattedFilesRemaining {
                        Text("• \(filesLeft)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let timeRemaining = timeRemaining {
                        Text("• \(timeRemaining)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var controlPanel: some View {
        Card {
            VStack(spacing: 16) {
                // Camera Label Settings
                cameraLabelSection
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                // Verification Mode
                verificationModeSection
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                // Action buttons
                actionSection
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var cameraLabelSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    cameraLabelExpanded.toggle()
                    NotificationCenter.default.post(name: .cameraLabelExpandedChanged, object: nil)
                }
            } label: {
                HStack {
                    Image(systemName: cameraLabelExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    
                    Text("Destination Folder Labeling")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    if !cameraLabel.destinationLabelSettings.label.isEmpty {
                        Text(cameraLabel.destinationLabelSettings.label)
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.2))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if cameraLabelExpanded {
                VStack(spacing: 12) {
                    // Show camera fingerprint if detected
                    if let fingerprint = cameraLabel.currentFingerprint {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.blue.opacity(0.5))
                            Text("Detected: \(fingerprint.displayName)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                        }
                    }
                    
                    Text("Folders will be labeled when copied to destinations")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    CameraLabelView(
                        settings: $coordinator.cameraLabelViewModel.destinationLabelSettings,
                        detectedCamera: cameraLabel.detectedCamera,
                        fingerprint: cameraLabel.currentFingerprint,
                        sourceURL: fileSelection.sourceURL
                    )
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
    }
    
    @ViewBuilder
    private var verificationModeSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    verificationModeExpanded.toggle()
                    NotificationCenter.default.post(name: .verificationModeExpandedChanged, object: nil)
                }
            } label: {
                HStack {
                    Image(systemName: verificationModeExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    
                    Text("Verification Mode")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("(\(coordinator.verificationMode.rawValue))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    // Show MHL badge if current mode requires it
                    if coordinator.verificationMode.requiresMHL {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 8))
                            Text("MHL")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.2))
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if verificationModeExpanded {
                VStack(spacing: 8) {
                    ForEach(VerificationMode.allCases) { mode in
                        HStack {
                            Image(systemName: coordinator.verificationMode == mode ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(coordinator.verificationMode == mode ? .green : .white.opacity(0.3))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(mode.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    if mode.requiresMHL {
                                        HStack(spacing: 3) {
                                            Image(systemName: "doc.text.fill")
                                                .font(.system(size: 8))
                                            Text("MHL")
                                                .font(.system(size: 9, weight: .semibold))
                                        }
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.orange.opacity(0.2))
                                        )
                                    }
                                    
                                    Spacer()
                                    
                                    // Time estimate
                                    if let estimate = getTimeEstimate(for: mode) {
                                        Text(estimate)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.blue.opacity(0.8))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(Color.blue.opacity(0.15))
                                            )
                                    }
                                }
                                
                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                coordinator.verificationMode = mode
                                // Save preference
                                coordinator.saveVerificationMode()
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
    }
    
    @ViewBuilder
    private var actionSection: some View {
        HStack {
            // Report toggle
            Toggle("Create PDF & CSV Report", isOn: $coordinator.settingsViewModel.prefs.makeReport)
                .toggleStyle(.switch)
                .tint(.green)

            Spacer()

            // Time estimate (when available)
            if let estimate = coordinator.timeEstimate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(estimate.formatted)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(estimate.speedSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.trailing, 16)
            } else if coordinator.isCalculatingEstimate {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 16)
            }

            // Action button
            Button {
                coordinator.switchMode(to: .copyAndVerify)
                coordinator.startOperation()
            } label: {
                Label("Copy & Verify", systemImage: "arrow.right.doc.on.clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.canStartOperation)
        }
    }
    
    // MARK: - Time Estimation
    @State private var modeEstimates: [VerificationMode: String] = [:]

    private func getTimeEstimate(for mode: VerificationMode) -> String? {
        return modeEstimates[mode]
    }

    private func updateModeEstimates() {
        guard let sourceURL = fileSelection.sourceURL,
              !fileSelection.destinationURLs.isEmpty,
              let totalBytes = fileSelection.sourceFolderInfo?.totalSize,
              totalBytes > 0 else {
            modeEstimates = [:]
            return
        }

        Task {
            var estimates: [VerificationMode: String] = [:]
            for mode in VerificationMode.allCases {
                if let estimate = await DriveBenchmarkService.shared.estimateTransferTime(
                    sourceURL: sourceURL,
                    destinationURLs: fileSelection.destinationURLs,
                    totalBytes: totalBytes,
                    verificationMode: mode
                ) {
                    estimates[mode] = estimate.formatted
                }
            }
            await MainActor.run {
                modeEstimates = estimates
            }
        }
    }
    
    private func openFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
