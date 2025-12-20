// CopyAndVerifyView.swift - Main copy and verify interface for iPad
import SwiftUI

struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var cameraLabelExpanded = false
    @State private var verificationModeExpanded = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Enhanced header with professional branding
            CopyAndVerifyHeaderView()
            
            // Full interface
            VStack(spacing: 20) {
                // Enhanced source and destination selection with HorizontalFlow-like design
                EnhancedSourceDestinationView(coordinator: coordinator)
                
                // Collapsible destination folder labeling section (matching macOS)
                CollapsibleLabelingSection(
                    coordinator: coordinator,
                    isExpanded: $cameraLabelExpanded
                )
                
                // Collapsible verification mode section (matching macOS)
                CollapsibleVerificationSection(
                    coordinator: coordinator,
                    isExpanded: $verificationModeExpanded
                )
                
                // Report settings toggle
                ReportToggleCard(coordinator: coordinator)
                
                // Enhanced start transfer button
                StartTransferButtonView(coordinator: coordinator)
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: cameraLabelExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: verificationModeExpanded)
    }
}

// MARK: - Enhanced Components (matching macOS sophistication)

struct CopyAndVerifyHeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                Text("COPY & VERIFY")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text("Copy files to backup destinations with integrity verification")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
        }
    }
}

struct EnhancedSourceDestinationView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        HStack(spacing: 16) {
            // Source section (left side)
            ProfessionalSourceCard(coordinator: coordinator)
                .frame(maxWidth: .infinity)
            
            // Arrow connector
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            
            // Destinations section (right side)  
            DestinationsFlowView(coordinator: coordinator)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// CompactOperationView removed as it is handled by ModularContentView switching to OperationProgressView

struct ProfessionalSourceCard: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("SOURCE FOLDER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Spacer()
                
                if coordinator.sourceURL != nil && !coordinator.isOperationInProgress {
                    Button {
                        coordinator.sourceURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Content
            if let sourceURL = coordinator.sourceURL {
                // Selected state
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sourceURL.lastPathComponent)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            
                            if let folderInfo = coordinator.sourceFolderInfo {
                                HStack(spacing: 8) {
                                    Text("\(folderInfo.formattedFileCount) files")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Text("•")
                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    Text(folderInfo.formattedSize)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Text(sourceURL.path)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(2)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Camera detection badge
                    if let detectedCamera = coordinator.detectedCamera {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                            Text(detectedCamera.displayName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.15))
                        )
                    }
                }
            } else {
                // Empty state
                Button {
                    Task { 
                        await coordinator.selectSourceFolder()
                    }
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.3))
                        
                        VStack(spacing: 4) {
                            Text("Select Source Folder")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Text("Choose the folder containing files to copy")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(coordinator.sourceURL != nil ? Color.green.opacity(0.05) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(coordinator.sourceURL != nil ? Color.green.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct DestinationsFlowView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("DESTINATIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1.2)
                
                if !coordinator.destinationURLs.isEmpty {
                    Text("\(coordinator.destinationURLs.count) selected")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            if coordinator.destinationURLs.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Add backup drives")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Button("Add Destinations...") {
                        Task { await coordinator.addDestinationFolder() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            } else {
                // Vertical list of destination cards (for side-by-side layout)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(coordinator.destinationURLs, id: \.self) { url in
                            CompactDestinationCard(url: url, coordinator: coordinator)
                        }
                        
                        // Add more button
                        if !coordinator.isOperationInProgress {
                            Button {
                                Task { await coordinator.addDestinationFolder() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                    Text("Add More...")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

struct EnhancedDestinationCard: View {
    let url: URL
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 10) {
            // Header with remove button
            HStack {
                Spacer()
                if !coordinator.isOperationInProgress {
                    Button {
                        coordinator.removeDestinationFolder(url)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 14)
            
            // Drive icon
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
            
            // Drive info
            VStack(spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("External Drive")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                // Path preview
                Text(url.path)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct CompactDestinationCard: View {
    let url: URL
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 14))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("External Drive")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if !coordinator.isOperationInProgress {
                Button {
                    coordinator.removeDestinationFolder(url)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct CollapsibleLabelingSection: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "textformat")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    
                    Text("FOLDER LABELING")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Preview when collapsed
                    if !isExpanded && !coordinator.cameraLabelSettings.label.isEmpty {
                        Text("\"\(coordinator.cameraLabelSettings.label)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    Divider().overlay(Color.white.opacity(0.1))
                    
                    VStack(spacing: 16) {
                        // Camera label field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Camera Label")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            
                            TextField(
                                "Enter camera name (e.g., A-Cam, B-Cam)",
                                text: Binding(
                                    get: { coordinator.cameraLabelSettings.label },
                                    set: { coordinator.cameraLabelSettings.label = $0 }
                                )
                            )
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                                .foregroundColor(.white)
                        }
                        
                        // Quick presets (wrapped layout)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Presets")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 60), spacing: 8)
                            ], spacing: 8) {
                                ForEach(["A-Cam", "B-Cam", "C-Cam", "Main", "Audio", "Drone"], id: \.self) { preset in
                                    Button {
                                        coordinator.cameraLabelSettings.label = preset
                                    } label: {
                                        Text(preset)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.orange.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Settings grid
                        VStack(spacing: 12) {
                            HStack(spacing: 16) {
                                // Position
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Position")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    HStack(spacing: 6) {
                                        positionChip(title: "Prefix", position: .prefix)
                                        positionChip(title: "Suffix", position: .suffix)
                                    }
                                }
                                
                                Spacer()
                                
                                // Separator
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Separator")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    HStack(spacing: 4) {
                                        ForEach(CameraLabelSettings.Separator.allCases.prefix(3), id: \.self) { sep in
                                            separatorChip(sep)
                                        }
                                    }
                                }
                            }
                            
                            // Toggles
                            VStack(spacing: 8) {
                                Toggle(
                                    "Auto-number if folder exists",
                                    isOn: Binding(
                                        get: { coordinator.cameraLabelSettings.autoNumber },
                                        set: { coordinator.cameraLabelSettings.autoNumber = $0 }
                                    )
                                )
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))

                                Toggle(
                                    "Group files by camera type in subfolders",
                                    isOn: Binding(
                                        get: { coordinator.cameraLabelSettings.groupByCamera },
                                        set: { coordinator.cameraLabelSettings.groupByCamera = $0 }
                                    )
                                )
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 1.05, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helpers
    private func positionChip(title: String, position: CameraLabelSettings.LabelPosition) -> some View {
        let selected = coordinator.cameraLabelSettings.position == position
        return Button {
            coordinator.cameraLabelSettings.position = position
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(selected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.orange : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
    
    private func separatorChip(_ sep: CameraLabelSettings.Separator) -> some View {
        let selected = coordinator.cameraLabelSettings.separator == sep
        return Button {
            coordinator.cameraLabelSettings.separator = sep
        } label: {
            Text(sep.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(selected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.orange : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

struct CollapsibleVerificationSection: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    
                    Text("VERIFICATION MODE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Preview when collapsed
                    if !isExpanded {
                        HStack(spacing: 6) {
                            Text(coordinator.verificationMode.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green.opacity(0.8))
                            
                            if coordinator.verificationMode.requiresMHL {
                                Text("MHL")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.orange.opacity(0.15))
                                    )
                            }
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    Divider()
                        .overlay(Color.white.opacity(0.1))
                    
                    VStack(spacing: 8) {
                        ForEach(VerificationMode.allCases, id: \.self) { mode in
                            VerificationModeRow(coordinator: coordinator, mode: mode)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 1.05, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct VerificationModeRow: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let mode: VerificationMode
    
    var body: some View {
        let isSelected = coordinator.verificationMode == mode
        return Button { coordinator.verificationMode = mode } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .green : .white.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if mode.requiresMHL {
                            Text("MHL")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.orange.opacity(0.15))
                                )
                        }
                        
                        Spacer()
                    }
                    
                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                    
                    // Estimated time
                    if let sourceInfo = coordinator.sourceFolderInfo {
                        Text("Estimated time: \(mode.estimatedTime(fileCount: sourceInfo.fileCount))")
                            .font(.system(size: 11))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.green.opacity(0.08) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.green.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StartTransferButtonView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    private var canStartTransfer: Bool {
        coordinator.sourceURL != nil && 
        !coordinator.destinationURLs.isEmpty && 
        !coordinator.isOperationInProgress
    }
    
    private var buttonText: String {
        if coordinator.isOperationInProgress {
            return "Transfer in Progress..."
        } else if coordinator.sourceURL == nil {
            return "Select Source Folder"
        } else if coordinator.destinationURLs.isEmpty {
            return "Add Backup Destinations"
        } else {
            return "Start Copy & Verify"
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Transfer summary when ready
            if canStartTransfer, let sourceInfo = coordinator.sourceFolderInfo {
                HStack {
                    Text("Ready to copy \(sourceInfo.formattedFileCount) files (\(sourceInfo.formattedSize)) to \(coordinator.destinationURLs.count) destination\(coordinator.destinationURLs.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
            }
            
            // Main button
            Button {
                Task {
                    await coordinator.startOperation()
                }
            } label: {
                HStack(spacing: 10) {
                    if coordinator.isOperationInProgress {
                        ProgressView()
                            .scaleEffect(0.9)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: canStartTransfer ? "play.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Text(buttonText)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canStartTransfer ? 
                              LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                              LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(canStartTransfer ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .opacity(canStartTransfer ? 1.0 : 0.6)
            }
            .disabled(!canStartTransfer)
            .buttonStyle(.plain)
        }
    }
}

struct ReportToggleCard: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Generate Reports")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Create PDF & CSV reports after transfer")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $coordinator.reportSettings.makeReport)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(coordinator.reportSettings.makeReport ? Color.blue.opacity(0.05) : Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(coordinator.reportSettings.makeReport ? Color.blue.opacity(0.15) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}
