// ContextualDestinationPopup.swift - Contextual popup for destination details
import SwiftUI

struct ContextualDestinationPopup: View {
    let destination: URL
    let progress: Double
    let transferState: CompactTransferCard.TransferState
    let currentFile: String?
    let sourceFrame: CGRect
    @Binding var isShowing: Bool
    
    @State private var animatedProgress: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Invisible overlay to detect clicks outside
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissPopup()
                    }
                
                // Popup content
                VStack(spacing: 0) {
                    // Arrow pointing to source
                    arrowView
                    
                    // Main popup content
                    popupContent
                }
                .position(popupPosition(in: geometry))
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        scale = 1.0
                        opacity = 1.0
                    }
                    withAnimation(.easeInOut(duration: 0.6).delay(0.1)) {
                        animatedProgress = progress
                    }
                }
            }
        }
    }
    
    // MARK: - Arrow View
    @ViewBuilder
    private var arrowView: some View {
        Triangle()
            .fill(Color.black.opacity(0.9))
            .frame(width: 16, height: 8)
            .offset(y: 4)
    }
    
    // MARK: - Popup Content
    @ViewBuilder
    private var popupContent: some View {
        VStack(spacing: 12) {
            // Header
            headerSection
            
            // Progress or Info Section
            if transferState == .copying || transferState == .verifying {
                activeTransferSection
            } else {
                inactiveTransferSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .frame(width: 260)
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(driveTypeDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Status Badge
            statusBadge
        }
    }
    
    // MARK: - Active Transfer Section
    @ViewBuilder
    private var activeTransferSection: some View {
        VStack(spacing: 8) {
            // Progress Bar
            VStack(spacing: 4) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                ProgressView(value: animatedProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(transferState.color)
                    .frame(height: 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(2)
            }
            
            // Current File
            if let currentFile = currentFile {
                HStack {
                    Text("Current File")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text(currentFile)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            
            // Estimated Time
            HStack {
                Text("Est. Time Remaining")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                Text(estimatedTimeRemaining)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
    
    // MARK: - Inactive Transfer Section
    @ViewBuilder
    private var inactiveTransferSection: some View {
        VStack(spacing: 8) {
            // Drive Details
            VStack(spacing: 6) {
                detailRow("Capacity", driveCapacity)
                detailRow("Connection", connectionType)
                detailRow("Est. Transfer Time", estimatedTotalTime)
            }
            
            // Status Message
            HStack {
                Image(systemName: transferState.icon)
                    .font(.system(size: 12))
                    .foregroundColor(transferState.color)
                
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(transferState.color)
                
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Status Badge
    @ViewBuilder
    private var statusBadge: some View {
        Text(transferState.displayName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(transferState.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(transferState.color.opacity(0.15))
            )
    }
    
    // MARK: - Computed Properties
    private var driveTypeDescription: String {
        let name = destination.lastPathComponent
        if name.contains("T7") || name.contains("SSD") {
            return "SSD • USB 3.2"
        } else if name.contains("HDD") || name.contains("Seagate") || name.contains("WD") {
            return "HDD • USB 3.0"
        } else {
            return "External Drive"
        }
    }
    
    private var driveCapacity: String {
        let name = destination.lastPathComponent
        if name.contains("T7") {
            return "1TB"
        } else if name.contains("Black") {
            return "500GB"
        } else if name.contains("Seagate") {
            return "2TB"
        } else if name.contains("LaCie") {
            return "4TB"
        }
        return "Unknown"
    }
    
    private var connectionType: String {
        let name = destination.lastPathComponent
        if name.contains("T7") {
            return "USB 3.2 Gen 2"
        } else if name.contains("Black") {
            return "USB 3.2 Gen 1"
        } else {
            return "USB 3.0"
        }
    }
    
    private var estimatedTimeRemaining: String {
        let remainingProgress = 1.0 - progress
        let estimatedMinutes = Int(remainingProgress * 45) // Assume ~45 min total
        
        if estimatedMinutes < 1 {
            return "< 1 min"
        } else if estimatedMinutes < 60 {
            return "\(estimatedMinutes) min"
        } else {
            let hours = estimatedMinutes / 60
            let mins = estimatedMinutes % 60
            return "\(hours)h \(mins)m"
        }
    }
    
    private var estimatedTotalTime: String {
        let name = destination.lastPathComponent
        if name.contains("T7") || name.contains("SSD") {
            return "~25 min"
        } else if name.contains("HDD") {
            return "~45 min"
        } else {
            return "~35 min"
        }
    }
    
    private var statusMessage: String {
        switch transferState {
        case .queued: return "Ready to start"
        case .idle: return "Waiting to begin"
        case .copying: return "Copying files..."
        case .verifying: return "Verifying..."
        case .completed: return "Transfer complete"
        }
    }
    
    // MARK: - Position Calculation
    private func popupPosition(in geometry: GeometryProxy) -> CGPoint {
        let popupHeight: CGFloat = 180
        let popupWidth: CGFloat = 260
        
        // For now, use a fixed position that appears near the destination area
        // This is on the right side where destinations typically appear
        let targetX = geometry.size.width - popupWidth - 40 // 40px from right edge
        let targetY = 150 // Fixed Y position that works for most cases
        
        // Ensure it stays within bounds
        let boundedX = max(20, min(targetX, geometry.size.width - popupWidth - 20))
        let boundedY = max(20, min(CGFloat(targetY), geometry.size.height - popupHeight - 20))
        
        return CGPoint(x: boundedX, y: boundedY)
    }
    
    // MARK: - Actions
    private func dismissPopup() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 0.8
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isShowing = false
        }
    }
}

// MARK: - Triangle Arrow Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.opacity(0.1)
        
        ContextualDestinationPopup(
            destination: URL(fileURLWithPath: "/Volumes/Samsung T7 NVMe"),
            progress: 0.65,
            transferState: .copying,
            currentFile: "DSC00123.ARW",
            sourceFrame: CGRect(x: 100, y: 100, width: 200, height: 20),
            isShowing: .constant(true)
        )
    }
    .frame(width: 600, height: 400)
}