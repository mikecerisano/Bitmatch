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

struct AdaptiveModeNavigation: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let presentation: AdaptiveNavigationPresentation

    var body: some View {
        switch presentation {
        case .compact:
            HStack(spacing: 8) {
                Text("MODE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.46))
                Spacer()
                Menu {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                coordinator.currentMode = mode
                            }
                        } label: {
                            Label(mode.shortTitle, systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    Label(coordinator.currentMode.shortTitle, systemImage: coordinator.currentMode.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.09)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

        case .toolbar:
            HeaderTabsView(coordinator: coordinator)

        case .sidebar:
            VStack(alignment: .leading, spacing: 6) {
                Text("BITMATCH")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 8)
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            coordinator.currentMode = mode
                        }
                    } label: {
                        Label(mode.shortTitle, systemImage: mode.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(coordinator.currentMode == mode ? .white : .white.opacity(0.58))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 9).fill(coordinator.currentMode == mode ? Color.white.opacity(0.12) : .clear))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 208, alignment: .leading)
            .padding(16)
        }
    }
}
