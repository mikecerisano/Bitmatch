// Views/CopyAndVerify/CopyAndVerifyView.swift
import SwiftUI
import AppKit

struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var showReportSettings: Bool
    @Binding var cameraLabelExpanded: Bool
    @Binding var verificationModeExpanded: Bool
    
    @State private var showOperationError = false
    @State private var operationErrorMessage: String?
    @State private var showVerificationHelp = false

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

    private var readinessIssues: [String] {
        guard let sourceURL = fileSelection.sourceURL else {
            return fileSelection.destinationURLs.isEmpty ? [] : ["Select a source folder"]
        }

        var issues: [String] = []
        if fileSelection.destinationURLs.isEmpty {
            issues.append("Add at least one destination")
        }

        let uniquePaths = Set(fileSelection.destinationURLs.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        if uniquePaths.count != fileSelection.destinationURLs.count {
            issues.append("Remove duplicate destinations")
        }

        for destination in fileSelection.destinationURLs {
            if SafetyValidator.isProtectedSystemPath(destination) {
                issues.append("\(destination.lastPathComponent) is a system folder")
            } else if let issue = SafetyValidator.destinationSafetyIssue(source: sourceURL, destination: destination) {
                issues.append("\(destination.lastPathComponent): \(issue)")
            } else if let sourceSize = fileSelection.sourceFolderInfo?.totalSize,
                      let available = availableSpace(for: destination),
                      available < sourceSize + Int64(100 * 1024 * 1024) {
                issues.append("Not enough space on \(destination.lastPathComponent)")
            }
        }

        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: sourceURL,
                destinations: fileSelection.destinationURLs,
                settings: coordinator.cameraLabelViewModel.destinationLabelSettings
            )
        } catch {
            issues.append(error.localizedDescription)
        }

        return issues
    }

    private var readinessWarnings: [String] {
        var warnings: [String] = []
        if coordinator.verificationMode == .quick {
            warnings.append("Quick mode only checks file size. Standard SHA-256 is safer for production transfers.")
        }

        if let sourceSize = fileSelection.sourceFolderInfo?.totalSize {
            warnings.append(contentsOf: fileSelection.destinationURLs.compactMap { destination in
                guard let available = availableSpace(for: destination), available > 0 else { return nil }
                let ratio = Double(sourceSize) / Double(available)
                return ratio > 0.7 ? "Limited space on \(destination.lastPathComponent)" : nil
            })
        }

        return warnings
    }

    private var canStartCopy: Bool {
        coordinator.canStartOperation && readinessIssues.isEmpty
    }

    private var shouldShowReadiness: Bool {
        fileSelection.sourceURL != nil || !fileSelection.destinationURLs.isEmpty
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
        .alert("Error", isPresented: $showOperationError) {
            Button("OK") {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "An error occurred")
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

            // Pause/Resume button
            if coordinator.canPause || coordinator.canResume {
                Button {
                    coordinator.togglePause()
                } label: {
                    Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(coordinator.isPaused ? .green : .white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(coordinator.isPaused ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help(coordinator.isPaused ? "Resume" : "Pause")
            }

            // Cancel button
            Button {
                coordinator.cancelOperation()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help("Cancel")
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

                if shouldShowReadiness {
                    readinessSection

                    Divider()
                        .overlay(Color.white.opacity(0.1))
                }
                
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

                    Button {
                        showVerificationHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showVerificationHelp, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Verification Modes")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Quick: Compares file sizes only. Fast but less thorough.")
                                .font(.system(size: 11))
                            Text("Standard: Computes SHA-256 checksums to verify byte-for-byte integrity.")
                                .font(.system(size: 11))
                            Text("Paranoid: SHA-256 checksums + MHL report generation for archival proof.")
                                .font(.system(size: 11))
                        }
                        .padding(12)
                        .frame(width: 300)
                    }

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
    private var readinessSection: some View {
        let issues = readinessIssues
        let warnings = readinessWarnings
        let hasIssues = !issues.isEmpty
        let hasWarnings = !warnings.isEmpty
        let tint: Color = hasIssues ? .red : (hasWarnings ? .orange : .green)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hasIssues ? "exclamationmark.triangle.fill" : (hasWarnings ? "exclamationmark.triangle" : "checkmark.circle.fill"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(readinessTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Text(readinessDetail(issues: issues, warnings: warnings))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tint.opacity(0.18), lineWidth: 0.5)
                )
        )
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
                    .foregroundColor(canStartCopy ? .black : .white.opacity(0.45))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canStartCopy ? Color.green : Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canStartCopy)
        }
    }

    private var readinessTitle: String {
        if !readinessIssues.isEmpty {
            return "Needs attention"
        }
        if !readinessWarnings.isEmpty {
            return "Ready with warnings"
        }
        return "Ready to transfer"
    }

    private func readinessDetail(issues: [String], warnings: [String]) -> String {
        if let issue = issues.first {
            return issue
        }
        if let warning = warnings.first {
            return warning
        }
        guard let info = fileSelection.sourceFolderInfo else {
            return "Source and destination folders are selected."
        }
        let destinationText = "\(fileSelection.destinationURLs.count) destination\(fileSelection.destinationURLs.count == 1 ? "" : "s")"
        return "\(info.formattedFileCount) files, \(info.formattedSize), \(destinationText)"
    }

    private func availableSpace(for url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacity {
                return Int64(capacity)
            }
        } catch { }
        return nil
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
