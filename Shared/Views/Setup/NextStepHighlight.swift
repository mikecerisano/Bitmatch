import SwiftUI

/// Draws attention to the step the user has not taken yet (see
/// `TransferPlanPresentation.nextStep`): an accent border that pulses gently,
/// or a steady one when Reduce Motion is on. It replaces an error banner,
/// because a choice not made yet is not an error.
struct NextStepHighlight: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var strokeOpacity: Double {
        guard isActive else { return 0 }
        if reduceMotion { return 0.8 }
        return pulsing ? 0.9 : 0.4
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accentColor.opacity(strokeOpacity), lineWidth: 2)
                    .shadow(color: Color.accentColor.opacity(isActive && !reduceMotion && pulsing ? 0.45 : 0), radius: 8)
                    .allowsHitTesting(false)
            )
            .onAppear(perform: updatePulse)
            .onChange(of: isActive) { _, _ in updatePulse() }
            .onChange(of: reduceMotion) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard isActive, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) { pulsing = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulsing = true }
    }
}

extension View {
    func nextStepHighlight(_ isActive: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(NextStepHighlight(isActive: isActive, cornerRadius: cornerRadius))
    }
}
