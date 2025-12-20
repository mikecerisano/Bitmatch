// UI/BitMatchMainView.swift - Cross-platform main view
import SwiftUI

/// Main view that adapts to both macOS and iOS
struct BitMatchMainView: View {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some View {
#if os(iOS)
        iPadLayout
#else
        macOSLayout
#endif
    }
    
    @ViewBuilder
    private var iPadLayout: some View {
        NavigationSplitView {
            // iPad sidebar with mode selection
            iPadSidebar
        } detail: {
            // Main content area
            iPadMainContent
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    @ViewBuilder
    private var iPadSidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App title and logo
            VStack(alignment: .leading, spacing: 8) {
                Text("BitMatch")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Professional File Verification")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Mode selection
            VStack(alignment: .leading, spacing: 12) {
                Text("MODE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.5))
                
                ForEach(AppMode.allCases, id: \.self) { mode in
                    iPadModeButton(for: mode)
                }
            }
            
            Spacer()
            
            // Status summary
            if coordinator.isOperationInProgress {
                iPadStatusSummary
            }
        }
        .padding()
        .background(Color.black.gradient)
    }
    
    @ViewBuilder
    private func iPadModeButton(for mode: AppMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.4)) {
                coordinator.switchMode(to: mode)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 18))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.shortTitle)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if coordinator.currentMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(coordinator.currentMode == mode ? Color.white.opacity(0.1) : Color.clear)
        )
    }
    
    @ViewBuilder
    private var iPadStatusSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPERATION STATUS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 4) {
                let progress = coordinator.progressPercentage
                if progress > 0 {
                    Text("Progress: \(Int(progress))%")
                        .font(.system(size: 14, weight: .medium))
                }
                
                if let speed = coordinator.formattedSpeed {
                    Text("Speed: \(speed)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                if let timeRemaining = coordinator.formattedTimeRemaining {
                    Text("Time: \(timeRemaining)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .foregroundColor(.white)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    @ViewBuilder
    private var iPadMainContent: some View {
        VStack {
            // Mode-specific content
            Group {
                switch coordinator.currentMode {
                case .copyAndVerify:
                    iPadCopyAndVerifyView
                case .compareFolders:
                    iPadCompareFoldersView  
                case .masterReport:
                    iPadMasterReportView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.gradient)
    }
    
    @ViewBuilder
    private var iPadCopyAndVerifyView: some View {
        // Touch-optimized copy and verify interface
        ScrollView {
            VStack(spacing: 24) {
                // Source selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("SOURCE")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    PlatformFilePickerView(
                        title: "Select Source Folder",
                        subtitle: "Camera card or folder to copy from",
                        onFileSelected: { urls in
                            coordinator.fileSelectionViewModel.sourceURL = urls.first
                        }
                    )
                }
                
                // Destinations selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("BACKUP DESTINATIONS")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    PlatformFilePickerView(
                        title: "Select Backup Folders",
                        subtitle: "One or more backup destinations",
                        allowsMultipleSelection: true,
                        onFileSelected: { urls in
                            coordinator.fileSelectionViewModel.destinationURLs = urls
                        }
                    )
                }
                
                // Action buttons
                iPadActionButtons
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var iPadCompareFoldersView: some View {
        // Touch-optimized folder comparison interface
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 20) {
                    // Left folder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LEFT FOLDER")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        PlatformFilePickerView(
                            title: "Select Left Folder",
                            subtitle: "Source of truth",
                            onFileSelected: { urls in
                                coordinator.fileSelectionViewModel.leftURL = urls.first
                            }
                        )
                    }
                    
                    // Right folder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RIGHT FOLDER")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        PlatformFilePickerView(
                            title: "Select Right Folder",
                            subtitle: "Folder to verify",
                            onFileSelected: { urls in
                                coordinator.fileSelectionViewModel.rightURL = urls.first
                            }
                        )
                    }
                }
                
                iPadActionButtons
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var iPadMasterReportView: some View {
        Text("Master Report")
            .font(.title)
            .foregroundColor(.white)
    }
    
    @ViewBuilder
    private var iPadActionButtons: some View {
        VStack(spacing: 16) {
            // Start/Stop button
            Button {
                if coordinator.isOperationInProgress {
                    coordinator.cancelOperation()
                } else {
                    coordinator.startOperation()
                }
            } label: {
                HStack {
                    Image(systemName: coordinator.isOperationInProgress ? "stop.fill" : "play.fill")
                    Text(coordinator.isOperationInProgress ? "Cancel Operation" : "Start Verification")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(coordinator.canStartOperation ? Color.green : Color.gray)
                )
            }
            .disabled(!coordinator.canStartOperation && !coordinator.isOperationInProgress)
            .buttonStyle(.plain)
            
            // Verification mode selector
            if !coordinator.isOperationInProgress {
                iPadVerificationModeSelector
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder  
    private var iPadVerificationModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VERIFICATION MODE")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(VerificationMode.allCases, id: \.self) { mode in
                    Button {
                        coordinator.verificationMode = mode
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(mode.description)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(coordinator.verificationMode == mode ? Color.blue.opacity(0.3) : Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(coordinator.verificationMode == mode ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    @ViewBuilder
    private var macOSLayout: some View {
        // Use existing ContentView for macOS
        ContentView()
    }
}