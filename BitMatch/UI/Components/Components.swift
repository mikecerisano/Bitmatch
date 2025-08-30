// UI/Components/Components.swift
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom Button Style
struct CustomButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDestructive ? .red : .white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDestructive ? Color.red.opacity(0.15) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isDestructive ? Color.red.opacity(0.3) : Color.white.opacity(0.2),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Mode Selector
struct ModeSelectorView: View {
    @Binding var mode: AppMode
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach([AppMode.copyAndVerify, AppMode.compareFolders, AppMode.masterReport], id: \.self) { appMode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mode = appMode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appMode.icon)
                            .font(.system(size: 11))
                        Text(appMode.shortTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(mode == appMode ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36) // Ensure minimum touch target height
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(mode == appMode ? Color.white.opacity(0.15) : Color.clear)
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
    }
}

// MARK: - Completion View
struct CompletionView: View {
    let message: String
    let iconName: String
    let iconColor: Color
    let onNewTask: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconName)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(iconColor)
            
            Text(message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Button("Start New Task") {
                withAnimation {
                    onNewTask()
                }
            }
            .buttonStyle(CustomButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
        )
    }
}
