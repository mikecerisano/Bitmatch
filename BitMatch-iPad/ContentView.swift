// ContentView.swift - iPad interface EXACTLY matching old.png screenshot
import SwiftUI

// MARK: - Transfer Queue Models
struct QueuedTransfer: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let sourceFolderInfo: FolderInfo?
    let destinations: [URL]
    let state: TransferState
    let progress: Double
    let currentFile: String?
    let speed: String?
    let timeRemaining: String?
    var createdAt: Date = Date()
    
    enum TransferState {
        case idle
        case copying
        case verifying
        case completed
        case queued
        
        var icon: String {
            switch self {
            case .idle: return "folder.fill"
            case .copying: return "doc.on.doc.fill"
            case .verifying: return "checkmark.shield.fill"
            case .completed: return "checkmark.circle.fill"
            case .queued: return "clock.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .idle: return .white.opacity(0.5)
            case .copying: return .blue
            case .verifying: return .orange
            case .completed: return .green
            case .queued: return .yellow.opacity(0.8)
            }
        }
        
        var displayName: String {
            switch self {
            case .idle: return "Ready"
            case .copying: return "Copying"
            case .verifying: return "Verifying"
            case .completed: return "Completed"
            case .queued: return "Queued"
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var coordinator = SharedAppCoordinator()
    @State private var showingSettings = false
    @State private var showReportSettings = false
    @State private var cameraLabelExpanded = false
    @State private var verificationModeExpanded = false
    
    // Dev mode controls (temporary for testing)
    @State private var devModeEnabled = false
    
    // Transfer Queue State
    @State private var queuedTransfers: [QueuedTransfer] = []
    @State private var completedTransfers: [QueuedTransfer] = []
    @State private var showCompletedTransfers = false
    
    var body: some View {
        ZStack {
            // Background matching old screenshot
            Color.black.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Main content area (matching old.png exactly)
                mainContentArea
                
                // Report Settings sidebar (matching old.png exactly)
                if showReportSettings {
                    reportSettingsSidebar
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .onChange(of: coordinator.operationState) { oldValue, newValue in
            // Move completed transfers to completed section
            if oldValue == .inProgress && newValue == .completed {
                moveCurrentTransferToCompleted()
            }
        }
        .sheet(isPresented: $showingSettings) {
            // Simple settings modal (matching old.png functionality)
            NavigationView {
                VStack {
                    Text("Settings")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .background(Color.black)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingSettings = false
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    @ViewBuilder
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            // Header with gear icon (always visible)
            headerSection
            
            // Two-state architecture: Idle vs Operation
            if coordinator.isOperationInProgress {
                // OPERATION STATE: Show progress interface
                operationProgressView
                    .onAppear {
                        print("📱 UI switched to OPERATION view")
                    }
            } else {
                // IDLE STATE: Show file selection and settings  
                idleStateView
                    .onAppear {
                        print("📱 UI switched to IDLE view")
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Idle State View (file selection & settings)
    @ViewBuilder
    private var idleStateView: some View {
        VStack(spacing: 0) {
            // Top tabs (matching old.png exactly)
            topTabsSection
            
            // Main scrollable content
            ScrollView {
                VStack(spacing: 24) {
                    // Source and Destinations (matching old.png exactly)
                    sourceDestinationSection
                    
                    // Destination Folder Labeling (matching old.png exactly)
                    destinationLabelingSection
                    
                    // Verification Mode (matching old.png exactly)
                    verificationModeSection
                    
                    // Start Transfer Button
                    startTransferButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Operation Progress View (during transfers)
    @ViewBuilder
    private var operationProgressView: some View {
        ScrollView {
            VStack(spacing: 20) {
            // Current operation status
            if let progress = coordinator.progress {
                VStack(spacing: 16) {
                    // Overall progress
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Transfer Progress")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("\(Int(progress.overallProgress * 100))%")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        ProgressView(value: progress.overallProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .scaleEffect(y: 2.0)
                    }
                    
                    // Current file and stats
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Stage")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text(progress.currentStage.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Files")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text("\(progress.filesProcessed)/\(progress.totalFiles)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        if let currentFile = progress.currentFile {
                            HStack {
                                Text("Current File:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text(currentFile)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                            }
                        }
                        
                        if let speed = progress.formattedSpeed {
                            HStack {
                                Text("Speed:")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text(speed)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                                
                                Spacer()
                                
                                if let timeRemaining = progress.formattedTimeRemaining {
                                    Text("ETA: \(timeRemaining)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
            } else {
                // Fallback if no progress data
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)
                    
                    Text("Starting transfer...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
            }
            
            // Control buttons during operation
            HStack(spacing: 16) {
                Button {
                    coordinator.cancelOperation()
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
                // Transfer Queue Section (if dev mode enabled during transfers)
                if devModeEnabled {
                    transferQueueSection
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Transfer Queue Section
    @ViewBuilder
    private var transferQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Queue Header
            HStack {
                Text("TRANSFER QUEUE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.2)
                
                Spacer()
                
                if !queuedTransfers.isEmpty {
                    Text("\(queuedTransfers.count) PENDING")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.yellow.opacity(0.8))
                }
            }
            
            // Queued Transfers
            if !queuedTransfers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(queuedTransfers) { transfer in
                        transferQueueCard(transfer: transfer, isActive: false)
                    }
                }
            }
            
            // Add to Queue Button
            Button {
                addFakeTransferToQueue()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    Text("Add Camera Card to Queue")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Completed Transfers (Collapsible)
            if !completedTransfers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showCompletedTransfers.toggle()
                        }
                    } label: {
                        HStack {
                            Text("COMPLETED")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1.0)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("\(completedTransfers.count) DONE")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.green.opacity(0.8))
                                
                                Image(systemName: showCompletedTransfers ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if showCompletedTransfers {
                        VStack(spacing: 6) {
                            ForEach(completedTransfers.prefix(3).reversed(), id: \.id) { transfer in
                                transferQueueCard(transfer: transfer, isActive: false)
                                    .opacity(0.7)
                            }
                        }
                        .transition(.slide)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Transfer Queue Card
    @ViewBuilder
    private func transferQueueCard(transfer: QueuedTransfer, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            // Source info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: transfer.state.icon)
                        .font(.system(size: 12))
                        .foregroundColor(transfer.state.color)
                    
                    Text(transfer.sourceURL.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                if let folderInfo = transfer.sourceFolderInfo {
                    Text("\(folderInfo.fileCount) files • \(folderInfo.formattedSize)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Destinations count
            HStack(spacing: 4) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.8))
                
                Text("\(transfer.destinations.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // State info
            if isActive {
                VStack(alignment: .trailing, spacing: 2) {
                    if transfer.progress > 0 {
                        Text("\(Int(transfer.progress * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Text(transfer.state.displayName.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(transfer.state.color)
                }
            } else {
                Text(transfer.state.displayName.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(transfer.state.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isActive ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(transfer.state.color.opacity(0.3), lineWidth: isActive ? 1 : 0.5)
                )
        )
    }
    
    // MARK: - Queue Management Functions
    private func addFakeTransferToQueue() {
        // Generate fake source data inline since DevModeManager may not be available
        let fakeURL = URL(fileURLWithPath: "/Volumes/QUEUE_CAM_\(Int.random(in: 1...999))")
        let fileCount = Int.random(in: 100...500)
        let totalSize = Int64.random(in: 2_000_000_000...8_000_000_000)
        
        let sourceInfo = FolderInfo(
            url: fakeURL,
            fileCount: fileCount,
            totalSize: totalSize,
            lastModified: Date()
        )
        
        // Generate fake destinations
        let destinationNames = ["Samsung_T7_Queue", "SanDisk_Extreme_Queue", "LaCie_Rugged_Queue"]
        let selectedCount = Int.random(in: 2...3)
        let destinations = destinationNames.prefix(selectedCount).map { name in
            URL(fileURLWithPath: "/Volumes/\(name)")
        }
        
        let fakeTransfer = QueuedTransfer(
            sourceURL: fakeURL,
            sourceFolderInfo: sourceInfo,
            destinations: destinations,
            state: .queued,
            progress: 0,
            currentFile: nil,
            speed: nil,
            timeRemaining: nil
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            queuedTransfers.append(fakeTransfer)
        }
        
        print("📋 Added transfer to queue: \(fakeURL.lastPathComponent) → \(destinations.count) destinations")
    }
    
    private func moveCurrentTransferToCompleted() {
        // Create completed transfer from current operation
        guard let sourceURL = coordinator.sourceURL,
              !coordinator.destinationURLs.isEmpty else { return }
        
        let completedTransfer = QueuedTransfer(
            sourceURL: sourceURL,
            sourceFolderInfo: coordinator.sourceFolderInfo,
            destinations: coordinator.destinationURLs,
            state: .completed,
            progress: 1.0,
            currentFile: nil,
            speed: nil,
            timeRemaining: nil
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            completedTransfers.insert(completedTransfer, at: 0) // Add to beginning
            // Keep only last 5 completed transfers
            if completedTransfers.count > 5 {
                completedTransfers.removeLast()
            }
        }
        
        print("📋 Moved current transfer to completed")
    }
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            // Settings gear (matching old.png position)
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Dev Mode Controls (temporary for testing)
            if devModeEnabled {
                Button("Fill Test Data") {
                    fillFakeTestData()
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.2))
                .foregroundColor(.yellow)
                .cornerRadius(4)
                .buttonStyle(.plain)
            }
            
            // Dev Mode Toggle (temporary for testing)  
            Button {
                devModeEnabled.toggle()
            } label: {
                Image(systemName: devModeEnabled ? "ladybug.fill" : "ladybug")
                    .font(.system(size: 14))
                    .foregroundColor(devModeEnabled ? .yellow : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            
            // Report Settings toggle (matching Mac pattern)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showReportSettings.toggle()
                }
            } label: {
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundColor(showReportSettings ? .green : .white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var topTabsSection: some View {
        // EXACT copy of Mac ModeSelectorView
        HStack(spacing: 0) {
            ForEach([AppMode.copyAndVerify, AppMode.compareFolders, AppMode.masterReport], id: \.self) { appMode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        coordinator.currentMode = appMode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appMode.systemImage)
                            .font(.system(size: 11))
                        Text(appMode.shortTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(coordinator.currentMode == appMode ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36) // Ensure minimum touch target height
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(coordinator.currentMode == appMode ? Color.white.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle()) // Make entire button area clickable
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private var sourceDestinationSection: some View {
        // EXACT copy of Mac HorizontalFlowView layout
        HStack(spacing: 16) {
            // Source section (left) - matches Mac exactly
            compactSourceSection
                .frame(width: 200)
            
            // Arrow connector - matches Mac exactly
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            
            // Destinations section (right, takes remaining space) - matches Mac exactly
            compactDestinationsSection
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 120, maxHeight: 200) // Allow wrapping to second row like Mac
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Compact Source Section (matches Mac exactly)
    @ViewBuilder
    private var compactSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.2)
            
            if let sourceURL = coordinator.sourceURL {
                // Source selected - matches Mac layout exactly
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sourceURL.lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            // File count and size (like Mac)
                            if let folderInfo = coordinator.sourceFolderInfo {
                                Text("\(folderInfo.fileCount) files • \(folderInfo.formattedSize)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        
                        Spacer()
                        
                        if !coordinator.isOperationInProgress {
                            Button {
                                coordinator.sourceURL = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Camera detection badge (like Mac)
                    if let detectedCamera = coordinator.detectedCamera {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 8))
                            Text(detectedCamera.displayName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.15))
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
            } else {
                // Empty state - matches Mac exactly
                VStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Drop folder")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Button("Choose...") {
                        Task { await coordinator.selectSourceFolder() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                    )
                    .scaleEffect(0.9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // MARK: - Compact Destinations Section (matches Mac exactly)
    @ViewBuilder
    private var compactDestinationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESTINATIONS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.2)
            
            if coordinator.destinationURLs.isEmpty {
                // Empty state - matches Mac exactly
                VStack(spacing: 6) {
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
                    .scaleEffect(0.9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            } else {
                // Show destinations in flexible grid that uses available space better
                let gridColumns = [
                    GridItem(.flexible(minimum: 180, maximum: 280), spacing: 12),
                    GridItem(.flexible(minimum: 180, maximum: 280), spacing: 12), 
                    GridItem(.flexible(minimum: 180, maximum: 280), spacing: 12)
                ]
                
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(Array(coordinator.destinationURLs.enumerated()), id: \.element) { index, destination in
                        compactDestinationCard(for: destination, at: index)
                    }
                    
                    // Add more button (matches Mac exactly)
                    if !coordinator.isOperationInProgress {
                        Button {
                            Task { await coordinator.addDestinationFolder() }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Text("Add")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity, minHeight: 90) // Match destination card size
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Compact Destination Card (matches Mac with drive speed & priority)
    @ViewBuilder
    private func compactDestinationCard(for url: URL, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                if !coordinator.isOperationInProgress {
                    Button {
                        coordinator.removeDestinationFolder(url)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Drive speed and priority info (like Mac)
            let driveSpeed = detectDriveSpeed(for: url)
            let priority = getFastLanePriority(for: url, at: index)
            
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: driveSpeed.icon)
                        .font(.system(size: 7))
                    Text(driveSpeed.rawValue)
                        .font(.system(size: 8))
                }
                .foregroundColor(driveSpeed.color)
                
                if let priorityInfo = priority {
                    Text("•")
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text(priorityInfo.label)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(priorityInfo.color)
                }
                
                Spacer()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Drive Speed Detection (matches Mac system)
    private func detectDriveSpeed(for url: URL) -> DriveSpeed {
        // Simplified drive speed detection for iPad
        // In production, this would check actual drive characteristics
        if url.path.contains("SSD") || url.path.contains("T7") || url.path.contains("Samsung") {
            return .ssd
        } else if url.path.contains("HDD") || url.path.contains("WD") || url.path.contains("Seagate") {
            return .hdd
        } else {
            return .unknown
        }
    }
    
    // MARK: - Fast Lane Priority System (matches Mac)
    private func getFastLanePriority(for url: URL, at index: Int) -> (label: String, color: Color)? {
        let destinationCount = coordinator.destinationURLs.count
        
        if destinationCount <= 1 {
            return nil // No priority needed for single destination
        }
        
        switch index {
        case 0:
            return ("Priority", .green)
        case 1:
            return ("Next", .orange)
        default:
            return ("Queued", .white.opacity(0.5))
        }
    }
    
    // MARK: - Drive Speed Types (matches Mac)
    enum DriveSpeed: String, CaseIterable {
        case ssd = "SSD"
        case hdd = "HDD" 
        case unknown = "Drive"
        
        var icon: String {
            switch self {
            case .ssd: return "bolt.fill"
            case .hdd: return "opticaldisc"
            case .unknown: return "externaldrive"
            }
        }
        
        var color: Color {
            switch self {
            case .ssd: return .green
            case .hdd: return .orange
            case .unknown: return .white.opacity(0.5)
            }
        }
    }
    
    @ViewBuilder
    private var destinationLabelingSection: some View {
        VStack(spacing: 0) {
            // Header button (styled like old mockup)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    cameraLabelExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: cameraLabelExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    
                    Text("Destination Folder Labeling")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if !coordinator.cameraLabelSettings.label.isEmpty {
                        Text(coordinator.cameraLabelSettings.label)
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            // Expandable content (only show when expanded)
            if cameraLabelExpanded {
                VStack(alignment: .leading, spacing: 20) {
                // Quick Presets (exact match to old.png)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Presets")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(["A-Cam", "Main", "B-Cam", "C-Cam", "D-Cam", "Audio", "Drone"], id: \.self) { preset in
                            Button {
                                coordinator.cameraLabelSettings.label = preset
                            } label: {
                                Text(preset)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Custom Camera Label (exact match to old.png)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Camera Label")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter label (e.g., A-Cam)", text: $coordinator.cameraLabelSettings.label)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .colorScheme(.dark)
                }
                
                // Label Position and Separator (exact match to old.png)
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Label Position")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 8) {
                            ForEach(["Prefix", "Suffix"], id: \.self) { position in
                                Button {
                                    coordinator.cameraLabelSettings.position = position == "Prefix" ? .prefix : .suffix
                                } label: {
                                    Text(position)
                                        .font(.system(size: 12))
                                        .foregroundColor((position == "Prefix" && coordinator.cameraLabelSettings.position == .prefix) ||
                                                       (position == "Suffix" && coordinator.cameraLabelSettings.position == .suffix) ? .black : .white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill((position == "Prefix" && coordinator.cameraLabelSettings.position == .prefix) ||
                                                     (position == "Suffix" && coordinator.cameraLabelSettings.position == .suffix) ? Color.white : Color.white.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Separator")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 8) {
                            ForEach([("Space", " "), ("Dash (-)", "-"), ("Underscore (_)", "_")], id: \.0) { separator in
                                Button {
                                    coordinator.cameraLabelSettings.separator = CameraLabelSettings.Separator(rawValue: separator.1) ?? .underscore
                                } label: {
                                    Text(separator.0.contains("Underscore") ? "Underscore (_)" : separator.0)
                                        .font(.system(size: 12))
                                        .foregroundColor(coordinator.cameraLabelSettings.separator.rawValue == separator.1 ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(coordinator.cameraLabelSettings.separator.rawValue == separator.1 ? Color.green : Color.white.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Toggles (exact match to old.png)
                VStack(spacing: 12) {
                    HStack {
                        Text("Auto-number if folder exists")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Toggle("", isOn: $coordinator.cameraLabelSettings.autoNumber)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Group by camera type")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Toggle("", isOn: $coordinator.cameraLabelSettings.groupByCamera)
                                .toggleStyle(SwitchToggleStyle(tint: .white.opacity(0.3)))
                        }
                        
                        Text("Organize files into camera-specific subfolders")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var verificationModeSection: some View {
        VStack(spacing: 0) {
            // Header button (styled like old mockup)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    verificationModeExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: verificationModeExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    
                    Text("Verification Mode")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("(\(coordinator.verificationMode.rawValue.capitalized))")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            // Expandable content (only show when expanded)
            if verificationModeExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose verification method:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    VStack(spacing: 12) {
                        ForEach(VerificationMode.allCases, id: \.self) { mode in
                            Button {
                                coordinator.verificationMode = mode
                            } label: {
                                HStack {
                                    Image(systemName: coordinator.verificationMode == mode ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(coordinator.verificationMode == mode ? .blue : .white.opacity(0.3))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.rawValue.capitalized)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white)
                                        
                                        Text(mode.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(coordinator.verificationMode == mode ? Color.blue.opacity(0.1) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var startTransferButton: some View {
        VStack(spacing: 16) {
            // Transfer readiness status
            if canStartTransfer {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    Text("Ready to transfer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green)
                    
                    Spacer()
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    Text(transferStatusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
            }
            
            // Start Transfer Button
            Button {
                print("🔘 START button tapped!")
                if canStartTransfer && !coordinator.isOperationInProgress {
                    print("🔘 Starting operation...")
                    Task {
                        await coordinator.startOperation()
                    }
                } else {
                    print("🔘 Button disabled - canStart: \(canStartTransfer), inProgress: \(coordinator.isOperationInProgress)")
                }
            } label: {
                HStack(spacing: 8) {
                    if coordinator.isOperationInProgress {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        
                        Text("Transferring...")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        
                        Text("START")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48) // Ensure minimum touch target
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canStartTransfer && !coordinator.isOperationInProgress ? Color.blue : Color.white.opacity(0.3))
                )
                .contentShape(Rectangle()) // Make entire button area tappable
            }
            .buttonStyle(.plain)
            .disabled(!canStartTransfer || coordinator.isOperationInProgress)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Properties
    
    private var canStartTransfer: Bool {
        let hasSource = coordinator.sourceURL != nil
        let hasDestinations = !coordinator.destinationURLs.isEmpty
        let canStart = hasSource && hasDestinations
        
        // Debug logging
        if !canStart {
            print("🔘 Cannot start transfer - hasSource: \(hasSource), hasDestinations: \(hasDestinations)")
            if !hasSource {
                print("🔘 Missing source URL")
            }
            if !hasDestinations {
                print("🔘 Missing destinations (count: \(coordinator.destinationURLs.count))")
            }
        }
        
        return canStart
    }
    
    private var transferStatusMessage: String {
        if coordinator.sourceURL == nil && coordinator.destinationURLs.isEmpty {
            return "Select source and destination folders"
        } else if coordinator.sourceURL == nil {
            return "Select source folder"
        } else if coordinator.destinationURLs.isEmpty {
            return "Select destination folders"
        } else {
            return "Ready to transfer"
        }
    }
    
    @ViewBuilder
    private var reportSettingsSidebar: some View {
        // Exact replica of old.png report settings sidebar
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Report Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation {
                        showReportSettings = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .overlay(Color.white.opacity(0.1))
            
            // Report Format (exact match to old.png)
            VStack(alignment: .leading, spacing: 16) {
                Text("REPORT FORMAT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)
                
                VStack(spacing: 12) {
                    reportFormatRow(title: "PDF Report", isOn: $coordinator.reportSettings.generatePDF, hasCheckmark: true)
                    reportFormatRow(title: "CSV Spreadsheet", isOn: $coordinator.reportSettings.generateCSV, hasCheckmark: true)  
                    reportFormatRow(title: "JSON Data", isOn: .constant(false), hasCheckmark: false)
                }
            }
            
            // Company Information (exact match to old.png)
            VStack(alignment: .leading, spacing: 16) {
                Text("COMPANY INFORMATION")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Company Name")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Your Company", text: $coordinator.reportSettings.clientName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .colorScheme(.dark)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Project Title", text: $coordinator.reportSettings.projectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .colorScheme(.dark)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Technician")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Your Name", text: $coordinator.reportSettings.notes)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .colorScheme(.dark)
                    }
                }
            }
            
            // Branding (exact match to old.png)
            VStack(alignment: .leading, spacing: 16) {
                Text("BRANDING")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)
                
                Button {
                    // Add company logo functionality
                } label: {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.blue)
                        Text("Add Company Logo")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(20)
        .frame(width: 300)
        .background(Color.black.opacity(0.8))
    }
    
    @ViewBuilder
    private func reportFormatRow(title: String, isOn: Binding<Bool>, hasCheckmark: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            
            Spacer()
            
            if hasCheckmark {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 16, height: 16)
            }
        }
    }
    
    // MARK: - Dev Mode Helper (temporary for testing)
    
    private func fillFakeTestData() {
        print("🎭 Filling fake test data for iPad UI testing")
        
        // Generate fake source URL and info
        let cameraNames = ["A_CAM", "B_CAM", "MAIN_CAM", "BACKUP_CAM", "DRONE"]
        let selectedCamera = cameraNames.randomElement()!
        let sourceURL = URL(fileURLWithPath: "/Volumes/\(selectedCamera)")
        
        // Create fake folder info
        let fileCount = Int.random(in: 150...450)
        let totalSize = Int64.random(in: 2_000_000_000...8_000_000_000) // 2-8 GB
        let fakeFolderInfo = FolderInfo(
            url: sourceURL,
            fileCount: fileCount,
            totalSize: totalSize,
            lastModified: Date()
        )
        
        // Generate fake destination URLs
        let driveNames = ["SanDisk_Extreme_1TB", "Samsung_T7_2TB", "LaCie_Rugged_4TB"]
        let fakeDestinations = driveNames.map { name in
            URL(fileURLWithPath: "/Volumes/\(name)")
        }
        
        // Set fake data on coordinator
        coordinator.sourceURL = sourceURL
        coordinator.sourceFolderInfo = fakeFolderInfo
        coordinator.destinationURLs = fakeDestinations
        
        // Simulate camera detection
        coordinator.detectedCamera = CameraCard(
            name: "Sony A7S III",
            manufacturer: "Sony",
            model: "A7S III",
            fileCount: fileCount,
            totalSize: totalSize,
            detectionConfidence: 0.95,
            metadata: ["volumeName": selectedCamera]
        )
        
        print("📁 Fake source: \(sourceURL.lastPathComponent) - \(fileCount) files")
        print("📁 Fake destinations: \(fakeDestinations.map { $0.lastPathComponent }.joined(separator: ", "))")
    }
}