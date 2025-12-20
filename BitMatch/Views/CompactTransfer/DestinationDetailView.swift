// DestinationDetailView.swift - Detailed progress view for individual destinations
import SwiftUI

struct DestinationDetailView: View {
    let destination: URL
    let progress: Double
    let transferState: CompactTransferCard.TransferState
    let currentFile: String?
    
    @Environment(\.dismiss) private var dismiss
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Progress Section
            progressSection
            
            // Details Section
            detailsSection
            
            Spacer()
            
            // Close Button
            closeButton
        }
        .frame(width: 400, height: 300)
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = progress
            }
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(destination.lastPathComponent)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                // State Badge
                HStack(spacing: 4) {
                    Image(systemName: transferState.icon)
                        .font(.system(size: 12))
                        .foregroundColor(transferState.color)
                    
                    Text(transferState.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(transferState.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(transferState.color.opacity(0.15))
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - Progress Section
    @ViewBuilder
    private var progressSection: some View {
        VStack(spacing: 12) {
            // Large Progress Circle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        transferState.color,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Complete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Linear Progress Bar
            VStack(spacing: 4) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                ProgressView(value: animatedProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(transferState.color)
                    .frame(height: 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(3)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Details Section
    @ViewBuilder
    private var detailsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                detailRow("Path", destination.path)
                detailRow("Volume", destination.lastPathComponent)
                
                if let currentFile = currentFile {
                    detailRow("Current File", currentFile)
                }
                
                detailRow("Status", transferState.displayName)
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Close Button
    @ViewBuilder
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            HStack {
                Text("Close")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Transfer State Extension
extension CompactTransferCard.TransferState {
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing"
        case .copying: return "Copying"
        case .verifying: return "Verifying"
        case .completed: return "Completed"
        case .queued: return "Queued"
        }
    }
}

// MARK: - Preview
#Preview {
    DestinationDetailView(
        destination: URL(fileURLWithPath: "/Volumes/Samsung T7"),
        progress: 0.65,
        transferState: .copying,
        currentFile: "DSC00123.ARW"
    )
    .background(Color.black)
}
