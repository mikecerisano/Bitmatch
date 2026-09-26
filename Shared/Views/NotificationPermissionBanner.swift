import SwiftUI

/// A contextual, non-modal permission offer. Starting the transfer never
/// waits for either choice.
struct NotificationPermissionBanner: View {
    @ObservedObject var coordinator: SharedAppCoordinator

    var body: some View {
        if coordinator.showsNotificationPermissionPrompt {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                    Text(NotificationPermissionPromptPresentation.question)
                        .font(.callout.weight(.medium))
                }

                HStack {
                    Spacer()
                    Button(NotificationPermissionPromptPresentation.notNowTitle) {
                        coordinator.declineNotificationsFromPrompt()
                    }
                    Button(NotificationPermissionPromptPresentation.enableTitle) {
                        Task { await coordinator.enableNotificationsFromPrompt() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
        }
    }
}
