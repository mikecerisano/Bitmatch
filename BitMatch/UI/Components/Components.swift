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

/// The one high-emphasis action treatment used when BitMatch is ready to proceed.
struct PrimaryActionButtonStyle: ButtonStyle {
    var isEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isEnabled ? .black : .white.opacity(0.45))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isEnabled ? Color.green : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.white.opacity(isEnabled ? 0.11 : 0.06), lineWidth: 0.5)
            )
            .shadow(color: isEnabled ? Color.green.opacity(configuration.isPressed ? 0.12 : 0.22) : .clear, radius: 9, y: 3)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.75)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
                        Image(systemName: appMode.systemImage)
                            .font(.system(size: 11))
                        Text(appMode.rawValue)
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

struct CompactModeSelectorView: View {
    @Binding var mode: AppMode

    var body: some View {
        Menu {
            ForEach([AppMode.copyAndVerify, AppMode.compareFolders, AppMode.masterReport], id: \.self) { appMode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mode = appMode
                    }
                } label: {
                    Label(appMode.rawValue, systemImage: appMode.systemImage)
                }
            }
        } label: {
            Label(mode.rawValue, systemImage: mode.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.09)))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Transfer mode")
        .accessibilityValue(mode.rawValue)
    }
}

// MARK: - Completion View
struct CompletionView: View {
    let message: String
    let iconName: String
    let iconColor: Color
    let onNewTask: () -> Void
    @State private var didAppear = false
    @State private var pulse = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconName)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(iconColor)
                .scaleEffect(pulse ? 1.06 : 0.96)
                .opacity(didAppear ? 1 : 0)
                .shadow(color: iconColor.opacity(0.35), radius: pulse ? 14 : 4, x: 0, y: 0)
            
            Text(message)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 8)
            
            Button("Start New Task") {
                withAnimation {
                    onNewTask()
                }
            }
            .buttonStyle(CustomButtonStyle())
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 10)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                didAppear = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Toast View
struct ToastView: View {
    let icon: String
    let message: String
    let tint: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.black.opacity(0.6))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
}
