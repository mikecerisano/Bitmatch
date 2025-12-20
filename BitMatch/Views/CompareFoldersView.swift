// Views/CompareFoldersView.swift - Updated to use AppCoordinator
import SwiftUI
import AppKit

struct CompareFoldersView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var showReportSettings: Bool
    @Binding var verificationModeExpanded: Bool
    
    // Convenience accessors
    private var fileSelection: FileSelectionViewModel { coordinator.fileSelectionViewModel }
    private var progress: ProgressViewModel { coordinator.progressViewModel }
    private var settings: SettingsViewModel { coordinator.settingsViewModel }
    
    private var currentFileName: String? {
        if coordinator.isOperationInProgress,
           let lastPath = coordinator.results.last?.path {
            return URL(fileURLWithPath: lastPath).lastPathComponent
        }
        return nil
    }
    
    private var speed: String? {
        progress.formattedSpeed
    }
    
    private var timeRemaining: String? {
        progress.formattedTimeRemaining
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Horizontal comparison layout - top section
            HStack(spacing: 20) {
                // Left folder panel
                VStack(alignment: .center, spacing: 12) {
                    Text("LEFT FOLDER (SOURCE OF TRUTH)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(1.5)
                        .frame(maxWidth: .infinity, minHeight: 20)
                    
                    Card(
                        isSelected: fileSelection.leftURL != nil,
                        progress: coordinator.progressPercentage,
                        isActive: coordinator.isOperationInProgress,
                        currentFile: currentFileName,
                        speed: speed,
                        timeRemaining: timeRemaining,
                        showMHLBadge: coordinator.verificationMode == .paranoid && coordinator.isOperationInProgress,
                        isMHLGenerating: coordinator.operationViewModel.isGeneratingMHL,
                        isMHLGenerated: coordinator.operationViewModel.mhlGenerated,
                        mhlFileName: coordinator.operationViewModel.mhlFilePath,
                        onDrop: coordinator.isOperationInProgress ? nil : { url in fileSelection.leftURL = url }
                    ) {
                        folderContent(
                            url: fileSelection.leftURL,
                            info: fileSelection.leftFolderInfo,
                            isLoading: fileSelection.isFetchingLeftInfo,
                            isVerifying: coordinator.isOperationInProgress,
                            onChoose: { fileSelection.leftURL = $0 },
                            onClear: { fileSelection.leftURL = nil }
                        )
                    }
                    .disabled(coordinator.isOperationInProgress)
                }
                .frame(maxWidth: .infinity)
                
                // Right folder panel
                VStack(alignment: .center, spacing: 12) {
                    Text("RIGHT FOLDER (TO VERIFY)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(1.5)
                        .frame(maxWidth: .infinity, minHeight: 20)
                    
                    Card(
                        isSelected: fileSelection.rightURL != nil,
                        progress: coordinator.progressPercentage,
                        isActive: coordinator.isOperationInProgress,
                        currentFile: nil,
                        speed: nil,
                        timeRemaining: nil,
                        showMHLBadge: false,
                        isMHLGenerating: false,
                        isMHLGenerated: false,
                        mhlFileName: nil,
                        onDrop: coordinator.isOperationInProgress ? nil : { url in fileSelection.rightURL = url }
                    ) {
                        folderContent(
                            url: fileSelection.rightURL,
                            info: fileSelection.rightFolderInfo,
                            isLoading: fileSelection.isFetchingRightInfo,
                            isVerifying: coordinator.isOperationInProgress,
                            onChoose: { fileSelection.rightURL = $0 },
                            onClear: { fileSelection.rightURL = nil }
                        )
                    }
                    .disabled(coordinator.isOperationInProgress)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .frame(height: 180) // Fixed height for folder cards
            
            // Actions & Options section below horizontal layout - bottom panel
            if !coordinator.isOperationInProgress {
                Card {
                    VStack(spacing: 16) {
                        // Collapsible Verification Mode section
                        verificationModeSection
                        
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                        
                        // Action button
                        actionSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: coordinator.isOperationInProgress)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: fileSelection.leftURL)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: fileSelection.rightURL)
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
            
            // Action button
            Button {
                coordinator.switchMode(to: .compareFolders)
                coordinator.startOperation()
            } label: {
                Label("Verify", systemImage: "checkmark.shield.fill")
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
    
    @ViewBuilder
    private func folderContent(
        url: URL?,
        info: FolderInfo?,
        isLoading: Bool,
        isVerifying: Bool,
        onChoose: @escaping (URL) -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        if let url = url {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text(url.path)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let info = info {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(info.formattedFileCount)
                            .font(.system(size: 11))
                        Text(info.formattedSize)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
                
                // Only show X button when NOT verifying
                if !isVerifying {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            HStack {
                Text("Drop a folder or click Choose...")
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Button("Choose...") {
                    if let newUrl = openFolderPanel() {
                        onChoose(newUrl)
                    }
                }
                .buttonStyle(CustomButtonStyle())
            }
        }
    }
    
    
    private func openFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
