// CompactTransferCard.swift - Compact 60px height cards for queue-ready interface
import SwiftUI

// MARK: - Frame Preference Key
struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CompactTransferCard: View {
    let sourceURL: URL
    let sourceInfo: FolderInfo?
    let destinations: [URL]
    let transferState: TransferState
    let progress: Double
    let currentFile: String?
    let speed: String?
    let timeRemaining: String?
    let destinationProgress: [Double] // Individual progress for each destination
    
    @State private var hoveredDestinationIndex: Int? = nil
    
    // Popup callback
    let onDestinationTap: ((Int, URL, Double, CGRect) -> Void)?
    
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
            case .queued: return .gray
            }
        }
        
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Source info (compact)
            sourceSection
            
            // Middle: Progress and connection lines
            progressSection
            
            // Right: Destinations (compact)
            destinationsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: dynamicHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(transferState.color.opacity(strokeOpacity), lineWidth: 1)
                )
        )
        .scaleEffect(scaleEffect)
        .opacity(opacity)
    }
    
    // MARK: - Dynamic Properties
    
    private var dynamicHeight: CGFloat {
        // Base height calculation - account for destinations that need more space
        let destinationRowCount = max(1, destinations.count)
        let destinationHeight = CGFloat(destinationRowCount * 18 + 8) // 18px per row + padding
        
        let baseHeight: CGFloat
        switch transferState {
        case .copying, .verifying:
            baseHeight = 60 // Full height for active transfers
        case .queued:
            baseHeight = 45 // Reduced height for queued items
        case .completed:
            baseHeight = 40 // Even smaller for completed items
        case .idle:
            baseHeight = 60
        }
        
        // Ensure we have enough height for all destinations
        return max(baseHeight, destinationHeight + 24) // +24 for top/bottom padding
    }
    
    private var scaleEffect: CGFloat {
        switch transferState {
        case .copying, .verifying:
            return 1.0 // Full scale for active transfers
        case .queued:
            return 0.95 // Slightly smaller for queued
        case .completed:
            return 0.9 // Smallest for completed
        case .idle:
            return 1.0
        }
    }
    
    private var opacity: Double {
        switch transferState {
        case .copying, .verifying:
            return 1.0 // Full opacity for active
        case .queued:
            return 0.8 // Slightly faded for queued
        case .completed:
            return 0.6 // More faded for completed
        case .idle:
            return 1.0
        }
    }
    
    private var backgroundFill: Color {
        switch transferState {
        case .copying, .verifying:
            return Color.white.opacity(0.08) // Brighter for active
        case .queued:
            return Color.white.opacity(0.04) // Dimmer for queued
        case .completed:
            return Color.green.opacity(0.03) // Subtle green tint for completed
        case .idle:
            return Color.white.opacity(0.05)
        }
    }
    
    private var strokeOpacity: Double {
        switch transferState {
        case .copying, .verifying:
            return 0.5 // Strong border for active
        case .queued:
            return 0.2 // Subtle border for queued
        case .completed:
            return 0.3 // Medium border for completed
        case .idle:
            return 0.3
        }
    }
    
    // MARK: - Source Section
    @ViewBuilder
    private var sourceSection: some View {
        HStack(spacing: 8) {
            // Camera icon with state indicator
            ZStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                
                // State indicator badge
                if transferState != .idle {
                    Image(systemName: transferState.icon)
                        .font(.system(size: 8))
                        .foregroundColor(transferState.color)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.8))
                                .frame(width: 14, height: 14)
                        )
                        .offset(x: 8, y: -8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceURL.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let info = sourceInfo {
                    Text("\(info.fileCount) files • \(info.formattedSize)")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("Loading...")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(width: 120, alignment: .leading)
    }
    
    // MARK: - Progress Section  
    @ViewBuilder
    private var progressSection: some View {
        VStack(spacing: 4) {
            // Progress bar and metrics
            if transferState == .copying || transferState == .verifying {
                // Progress bar
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(transferState.color)
                    .frame(height: 4)
                
                // Metrics row
                HStack(spacing: 8) {
                    if let currentFile = currentFile {
                        Text(currentFile)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 8, weight: .semibold))
                        
                        if let speed = speed {
                            Text("•")
                            Text(speed)
                                .font(.system(size: 8))
                        }
                        
                        if let timeRemaining = timeRemaining {
                            Text("•")
                            Text(timeRemaining)
                                .font(.system(size: 8))
                        }
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .frame(height: 12)
            } else {
                // Status text for other states
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(transferState.color)
                    .frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Destinations Section
    @ViewBuilder  
    private var destinationsSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(Array(destinations.enumerated()), id: \.offset) { index, destination in
                destinationRow(destination, index: index)
            }
        }
        .frame(width: max(140, CGFloat(destinations.count * 35)), alignment: .trailing)
    }
    
    @ViewBuilder
    private func destinationRow(_ destination: URL, index: Int) -> some View {
        ZStack {
            // Background progress bar for this destination
            if transferState == .copying || transferState == .verifying {
                let destProgress = index < destinationProgress.count ? destinationProgress[index] : 0.0
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 16)
                        
                        // Progress fill with hover enhancement
                        RoundedRectangle(cornerRadius: 8)
                            .fill(transferState.color.opacity(hoveredDestinationIndex == index ? 0.6 : 0.4))
                            .frame(width: geometry.size.width * destProgress, height: 16)
                    }
                }
                .frame(height: 16)
            }
            
            HStack(spacing: 6) {
                // Fast Lane priority indicator
                let priority = getFastLanePriority(for: destination, at: index)
                if let priorityInfo = priority {
                    Image(systemName: priorityInfo.icon)
                        .font(.system(size: 6))
                        .foregroundColor(priorityInfo.color)
                }
                
                Text(destination.lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                // Individual progress percentage for active transfers
                if transferState == .copying || transferState == .verifying {
                    let destProgress = index < destinationProgress.count ? destinationProgress[index] : 0.0
                    Text("\(Int(destProgress * 100))%")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 18) // Increased to 18 for even better touch targets
        .contentShape(Rectangle()) // Make entire row clickable
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: FramePreferenceKey.self, value: geometry.frame(in: .global))
            }
        )
        .onPreferenceChange(FramePreferenceKey.self) { frame in
            // Store frame for this destination
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        // Store the frame for this destination
                    }
            }
        )
        .onTapGesture {
            // Calculate the global frame for this destination
            if let onTap = onDestinationTap {
                let progress = index < destinationProgress.count ? destinationProgress[index] : 0.0
                // Use a rough estimate for the frame - will be refined
                let estimatedFrame = CGRect(x: 0, y: CGFloat(index * 18), width: 140, height: 18)
                onTap(index, destination, progress, estimatedFrame)
            }
        }
        .onHover { isHovering in
            if isHovering && (transferState == .copying || transferState == .verifying) {
                hoveredDestinationIndex = index
                NSCursor.pointingHand.set()
            } else {
                hoveredDestinationIndex = nil
                NSCursor.arrow.set()
            }
        }
        .scaleEffect(hoveredDestinationIndex == index ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: hoveredDestinationIndex)
    }
    
    // MARK: - Helpers
    
    private var statusText: String {
        switch transferState {
        case .idle: return "Ready to transfer"
        case .copying: return "Copying..."
        case .verifying: return "Verifying..."
        case .completed: return "✓ Complete"
        case .queued: return "Queued"
        }
    }
    
    struct FastLanePriorityInfo {
        let icon: String
        let color: Color
    }
    
    private func getFastLanePriority(for destination: URL, at index: Int) -> FastLanePriorityInfo? {
        guard destinations.count > 1 else { return nil }
        
        // For now, simulate priority based on index
        // In real implementation, this would check actual drive speeds
        switch index {
        case 0: return FastLanePriorityInfo(icon: "bolt.fill", color: .green)
        case 1: return FastLanePriorityInfo(icon: "clock.fill", color: .orange)
        default: return FastLanePriorityInfo(icon: "pause.fill", color: .gray)
        }
    }
}