// HeaderTabsView.swift - Top navigation tabs component for iPad
import SwiftUI

struct HeaderTabsView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        topTabsSection
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
}