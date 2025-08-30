// Views/AnalyticsOptInView.swift
import SwiftUI

struct AnalyticsOptInView: View {
    @Binding var isShowing: Bool
    @State private var communityStats: AnalyticsSharing.CommunityStats?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Help Improve BitMatch")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Share anonymous transfer data to improve time estimates for everyone")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            
            // Privacy info
            VStack(alignment: .leading, spacing: 8) {
                privacyPoint(
                    icon: "checkmark.shield.fill",
                    text: "100% anonymous - no personal data",
                    color: .green
                )
                
                privacyPoint(
                    icon: "eye.slash.fill", 
                    text: "No file names, paths, or identifiers",
                    color: .blue
                )
                
                privacyPoint(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "Only transfer speed & verification data",
                    color: .orange
                )
                
                privacyPoint(
                    icon: "person.3.fill",
                    text: "Helps new users get accurate estimates",
                    color: .purple
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
            
            // Community impact (if available)
            if communityStats != nil {
                let stats = communityStats!
                VStack(spacing: 6) {
                    Text("Community Impact")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    
                    HStack(spacing: 16) {
                        statPill(
                            value: "\\(stats.totalTransfers)",
                            label: "transfers",
                            color: .green
                        )
                        
                        statPill(
                            value: "\\(String(format: \"%.1f\", stats.totalDataProcessedTB))TB",
                            label: "processed", 
                            color: .blue
                        )
                        
                        statPill(
                            value: "\\(Int(stats.averageAccuracyImprovement * 100))%",
                            label: "more accurate",
                            color: .orange
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button {
                    AnalyticsSharing.shared.isOptedIn = true
                    AnalyticsSharing.shared.markOptInPromptShown()
                    isShowing = false
                } label: {
                    Text("Help Improve BitMatch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(.plain)
                
                Button {
                    AnalyticsSharing.shared.isOptedIn = false
                    AnalyticsSharing.shared.markOptInPromptShown()
                    isShowing = false
                } label: {
                    Text("No Thanks")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            
            // Fine print
            Text("You can change this anytime in Settings")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(24)
        .frame(width: 400, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            loadCommunityStats()
        }
    }
    
    @ViewBuilder
    private func privacyPoint(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
    
    @ViewBuilder 
    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
    
    private func loadCommunityStats() {
        Task {
            communityStats = await AnalyticsSharing.shared.getCommunityStats()
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AnalyticsOptInView(isShowing: .constant(true))
    }
}