import SwiftUI

/// A deliberately small optional stage. It exposes saved destination metadata
/// but never credentials, private-key paths, passphrases, or host-key data.
struct RemoteBackupDestinationView: View {
    @ObservedObject var coordinator: AppCoordinator

    private var viewModel: PhotographerJobViewModel { coordinator.photographerJobViewModel }
    private var configuration: RemoteBackupConfiguration? { viewModel.activeJob?.remoteBackupConfiguration }
    private var isEnabled: Bool { configuration?.isEnabled == true }
    private var presentation: RemoteBackupDestinationPresentation {
        .make(isEnabled: isEnabled, profiles: viewModel.remoteProfiles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Toggle(isOn: Binding(get: { isEnabled }, set: setEnabled)) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(presentation.title).font(DesignSystem.Typography.body)
                    Spacer()
                    if !presentation.isExpanded {
                        Text(presentation.detail)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
            }
            .toggleStyle(.switch)

            if presentation.isExpanded {
                if viewModel.remoteProfiles.isEmpty {
                    Text("Add an agent-authenticated SFTP destination in Preferences before queueing off-site backup.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.warning)
                } else {
                    Picker("Destination", selection: Binding(get: { configuration?.destinationProfileID }, set: coordinator.selectRemoteProfile)) {
                        Text("Select saved destination").tag(UUID?.none)
                        ForEach(viewModel.remoteProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .accessibilityLabel("Off-site backup destination")

                    if let profile = viewModel.remoteProfiles.first(where: { $0.id == configuration?.destinationProfileID }) {
                        Text("SFTP · (profile.username)@(profile.host) · (profile.root.description)")
                            .font(DesignSystem.Typography.monoSmall)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text(profile.verificationMode == .sha256 ? "Remote SHA-256 verification required." : "Upload-only reports Uploaded · Unverified.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(profile.verificationMode == .sha256 ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.warning)
                    }
                    Text("Unknown or changed host keys require explicit confirmation before SSH-agent authentication. Read-back verification can use significant data.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium).fill(DesignSystem.Colors.background.opacity(0.35)))
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            coordinator.selectRemoteProfile(viewModel.remoteProfiles.first?.id)
        } else {
            coordinator.selectRemoteProfile(nil)
        }
    }
}
