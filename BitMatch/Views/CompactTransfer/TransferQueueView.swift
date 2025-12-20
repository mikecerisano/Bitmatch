// TransferQueueView.swift - Queue container for multiple transfers
import SwiftUI

struct TransferQueueView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var queuedTransfers: [QueuedTransfer] = []
    @State private var completedTransfers: [QueuedTransfer] = []
    @State private var showCompletedTransfers = false
    
    // Popup state
    @State private var showingDestinationPopup = false
    @State private var selectedDestination: URL?
    @State private var selectedProgress: Double = 0
    @State private var popupSourceFrame: CGRect = .zero
    @State private var selectedTransferState: CompactTransferCard.TransferState = .idle
    @State private var selectedCurrentFile: String?
    
    struct QueuedTransfer: Identifiable {
        let id = UUID()
        let sourceURL: URL
        let sourceInfo: FolderInfo?
        let destinations: [URL]
        let state: CompactTransferCard.TransferState
        let progress: Double
        let currentFile: String?
        let speed: String?
        let timeRemaining: String?
        let destinationProgress: [Double] // Individual progress for each destination
        var createdAt: Date = Date()
    }
    
    var body: some View {
        ZStack {
            // Main content
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    // Active transfer (if any)
                    if let activeTransfer = activeTransfer {
                        activeTransferSection(activeTransfer)
                    }
                    
                    // Queued transfers
                    if !queuedTransfers.isEmpty {
                        queuedTransfersSection
                    }
                    
                    // Completed transfers (collapsible)
                    if !completedTransfers.isEmpty {
                        completedTransfersSection
                    }
                    
                    // Add new transfer section (dev mode only)
                    if DevModeManager.shared.isDevModeEnabled && coordinator.isOperationInProgress {
                        addNewTransferSection
                    }
                    
                    // Empty state when no transfers
                    if activeTransfer == nil && queuedTransfers.isEmpty && completedTransfers.isEmpty && !coordinator.isOperationInProgress {
                        emptyQueueState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(maxHeight: 400) // Limit height to prevent overflow
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: queuedTransfers.count)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: completedTransfers.count)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: coordinator.isOperationInProgress)
            .onReceive(NotificationCenter.default.publisher(for: .addFakeQueueItem)) { _ in
                addFakeQueueItem()
            }
            
            // Top-level popup overlay
            if showingDestinationPopup, let destination = selectedDestination {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingDestinationPopup = false
                    }
                    .overlay(
                        ContextualDestinationPopup(
                            destination: destination,
                            progress: selectedProgress,
                            transferState: selectedTransferState,
                            currentFile: selectedCurrentFile,
                            sourceFrame: popupSourceFrame,
                            isShowing: $showingDestinationPopup
                        )
                        .position(x: 300, y: 150) // Fixed position that floats above everything
                    )
            }
        }
    }
    
    // MARK: - Section Views
    
    @ViewBuilder
    private func activeTransferSection(_ activeTransfer: QueuedTransfer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACTIVE TRANSFER")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                
                Spacer()
                
                // Pulse indicator for active transfer
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseScale)
                    
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                        .tracking(0.5)
                }
            }
            
            CompactTransferCard(
                sourceURL: activeTransfer.sourceURL,
                sourceInfo: activeTransfer.sourceInfo,
                destinations: activeTransfer.destinations,
                transferState: activeTransfer.state,
                progress: activeTransfer.progress,
                currentFile: activeTransfer.currentFile,
                speed: activeTransfer.speed,
                filesRemaining: coordinator.progressViewModel.formattedFilesRemaining,
                timeRemaining: activeTransfer.timeRemaining,
                destinationProgress: activeTransfer.destinationProgress,
                onDestinationTap: { index, destination, progress, frame in
                    selectedDestination = destination
                    selectedProgress = progress
                    popupSourceFrame = frame
                    selectedTransferState = activeTransfer.state
                    selectedCurrentFile = activeTransfer.currentFile
                    showingDestinationPopup = true
                }
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        }
    }
    
    @State private var pulseScale: CGFloat = 1.0
    
    @ViewBuilder
    private var queuedTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QUEUED TRANSFERS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                
                Spacer()
                
                Text("\(queuedTransfers.count) PENDING")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.8))
                    .tracking(0.5)
            }
            
            ForEach(queuedTransfers) { transfer in
                CompactTransferCard(
                    sourceURL: transfer.sourceURL,
                    sourceInfo: transfer.sourceInfo,
                    destinations: transfer.destinations,
                    transferState: transfer.state,
                    progress: transfer.progress,
                    currentFile: transfer.currentFile,
                    speed: transfer.speed,
                    filesRemaining: nil,
                    timeRemaining: transfer.timeRemaining,
                    destinationProgress: transfer.destinationProgress,
                    onDestinationTap: { index, destination, progress, frame in
                        selectedDestination = destination
                        selectedProgress = progress
                        popupSourceFrame = frame
                        selectedTransferState = transfer.state
                        selectedCurrentFile = transfer.currentFile
                        showingDestinationPopup = true
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .move(edge: .trailing)).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .move(edge: .leading)).combined(with: .opacity)
                ))
            }
        }
    }
    
    @ViewBuilder
    private var completedTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showCompletedTransfers.toggle()
                }
            } label: {
                HStack {
                    Text("COMPLETED TRANSFERS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(1)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("\(completedTransfers.count) DONE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.green.opacity(0.8))
                            .tracking(0.5)
                        
                        Image(systemName: showCompletedTransfers ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .buttonStyle(.plain)
            
            if showCompletedTransfers {
                ForEach(completedTransfers.suffix(5).reversed(), id: \.id) { transfer in
                    CompactTransferCard(
                        sourceURL: transfer.sourceURL,
                        sourceInfo: transfer.sourceInfo,
                        destinations: transfer.destinations,
                        transferState: .completed,
                        progress: 1.0,
                        currentFile: nil,
                        speed: nil,
                        filesRemaining: nil,
                        timeRemaining: nil,
                        destinationProgress: Array(repeating: 1.0, count: transfer.destinations.count),
                        onDestinationTap: { index, destination, progress, frame in
                            selectedDestination = destination
                            selectedProgress = progress
                            popupSourceFrame = frame
                            selectedTransferState = .completed
                            selectedCurrentFile = nil
                            showingDestinationPopup = true
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
        }
    }
    
    // MARK: - Active Transfer
    private var activeTransfer: QueuedTransfer? {
        guard coordinator.isOperationInProgress else { return nil }
        
        let state: CompactTransferCard.TransferState = {
            switch coordinator.operationViewModel.state {
            case .copying: return .copying
            case .verifying: return .verifying
            case .completed: return .completed
            case .inProgress: return .preparing
            default: return .idle
            }
        }()
        
        let progress = coordinator.progressPercentage
        // Prefer average data rate (bytes/s) in human readable form
        let speed = coordinator.progressViewModel.formattedAverageDataRate
        let timeRemaining = coordinator.progressViewModel.formattedTimeRemaining
        let currentFile = getCurrentFileName()
        
        guard let sourceURL = coordinator.fileSelectionViewModel.sourceURL else { return nil }
        
        return QueuedTransfer(
            sourceURL: sourceURL,
            sourceInfo: coordinator.fileSelectionViewModel.sourceFolderInfo,
            destinations: coordinator.fileSelectionViewModel.destinationURLs,
            state: state,
            progress: progress,
            currentFile: currentFile,
            speed: speed,
            timeRemaining: timeRemaining,
            destinationProgress: coordinator.progressViewModel.destinationProgressFractions(
                expectedCount: coordinator.fileSelectionViewModel.destinationURLs.count
            )
        )
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private var addNewTransferSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD TO QUEUE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
            
            Button {
                DevModeManager.shared.addFakeQueueItem(coordinator: coordinator)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    Text("Add Camera Card to Queue")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("⌥⌘Q")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var emptyQueueState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No transfers in queue")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            if DevModeManager.shared.isDevModeEnabled {
                Button {
                    DevModeManager.shared.startFakeTransfer(coordinator: coordinator)
                } label: {
                    Text("Start Test Transfer")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 80)
    }
    
    // MARK: - Helper Functions
    
    private func getCurrentFileName() -> String? {
        if coordinator.isOperationInProgress,
           let lastPath = coordinator.results.last?.path {
            return URL(fileURLWithPath: lastPath).lastPathComponent
        }
        return nil
    }
    
    private func generateDestinationProgress(
        for destinations: [URL],
        overallProgress: Double,
        state: CompactTransferCard.TransferState
    ) -> [Double] {
        guard !destinations.isEmpty else { return [] }
        
        switch state {
        case .copying:
            // Simulate staggered copying - first destination gets ahead
            return destinations.enumerated().map { index, _ in
                let stagger = Double(index) * 0.1 // Each destination starts 10% later
                let adjustedProgress = max(0, min(1, overallProgress - stagger + 0.1))
                return adjustedProgress
            }
        case .verifying:
            // During verification, all destinations should be at similar progress
            let variance = 0.05 // 5% variance between destinations
            return destinations.enumerated().map { index, _ in
                let randomVariance = Double.random(in: -variance...variance)
                return max(0, min(1, overallProgress + randomVariance))
            }
        case .completed:
            return Array(repeating: 1.0, count: destinations.count)
        case .queued, .idle, .preparing:
            return Array(repeating: 0.0, count: destinations.count)
        }
    }
    
    private func addFakeQueueItem() {
        let (fakeSource, fakeSourceInfo) = DevModeManager.shared.generateFakeSource()
        let fakeDestinations = DevModeManager.shared.generateFakeDestinations()
        
        let fakeTransfer = QueuedTransfer(
            sourceURL: fakeSource,
            sourceInfo: fakeSourceInfo,
            destinations: fakeDestinations.map { $0.url },
            state: .queued,
            progress: 0,
            currentFile: nil,
            speed: nil,
            timeRemaining: nil,
            destinationProgress: Array(repeating: 0.0, count: fakeDestinations.count)
        )
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            queuedTransfers.append(fakeTransfer)
        }
        
        // Simulate completed transfers occasionally
        if Int.random(in: 1...10) <= 3 { // 30% chance
            let completedTransfer = QueuedTransfer(
                sourceURL: fakeSource,
                sourceInfo: fakeSourceInfo,
                destinations: fakeDestinations.map { $0.url },
                state: .completed,
                progress: 1.0,
                currentFile: nil,
                speed: nil,
                timeRemaining: nil,
                destinationProgress: Array(repeating: 1.0, count: fakeDestinations.count),
                createdAt: Date().addingTimeInterval(-Double.random(in: 60...3600)) // 1min-1hr ago
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    completedTransfers.insert(completedTransfer, at: 0)
                    // Keep only recent completed transfers
                    if completedTransfers.count > 10 {
                        completedTransfers.removeLast()
                    }
                }
            }
        }
    }
}
