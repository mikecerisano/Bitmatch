import SwiftUI

/// A deliberately small optional stage. It exposes saved destination metadata
/// but never credentials, private-key paths, passphrases, or host-key data.
struct RemoteBackupDestinationView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var isStageEnabled = false
    @State private var showingDestinations = false

    private var viewModel: PhotographerJobViewModel { coordinator.photographerJobViewModel }
    private var configuration: RemoteBackupConfiguration? { viewModel.activeJob?.remoteBackupConfiguration }
    private var isEnabled: Bool { isStageEnabled }
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
                    Button("Manage destinations") { showingDestinations = true }
                        .font(DesignSystem.Typography.caption)
                } else {
                    Picker("Destination", selection: Binding(get: { configuration?.destinationProfileID }, set: coordinator.selectRemoteProfile)) {
                        Text("Select saved destination").tag(UUID?.none)
                        ForEach(viewModel.remoteProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .accessibilityLabel("Off-site backup destination")

                    if let profile = viewModel.remoteProfiles.first(where: { $0.id == configuration?.destinationProfileID }) {
                        Text("SFTP · \(profile.username)@\(profile.host) · \(profile.root.description)")
                            .font(DesignSystem.Typography.monoSmall)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Text(profile.verificationMode == .sha256 ? "Remote SHA-256 verification required." : "Upload-only reports Uploaded · Unverified.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(profile.verificationMode == .sha256 ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.warning)
                    }
                    Button("Manage destinations") { showingDestinations = true }
                        .font(DesignSystem.Typography.caption)
                    Text("Unknown or changed host keys require explicit confirmation before SSH-agent authentication. Read-back verification can use significant data.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium).fill(DesignSystem.Colors.background.opacity(0.35)))
        .onAppear { isStageEnabled = configuration?.isEnabled == true }
        .sheet(isPresented: $showingDestinations) {
            RemoteBackupDestinationManager(viewModel: viewModel, coordinator: coordinator)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isStageEnabled = enabled
        if enabled {
            if let profileID = viewModel.remoteProfiles.first?.id { coordinator.selectRemoteProfile(profileID) }
        } else {
            coordinator.selectRemoteProfile(nil)
        }
    }
}

struct RemoteBackupDestinationManager: View {
    @ObservedObject var viewModel: PhotographerJobViewModel
    let coordinator: AppCoordinator
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var root = "Backups"
    @State private var verification: RemoteVerificationMode = .sha256
    @State private var editingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SFTP destinations").font(.headline)
                Spacer()
                if showsDoneButton { Button("Done") { dismiss() } }
            }
            List {
                ForEach(viewModel.remoteProfiles) { profile in
                    HStack { VStack(alignment: .leading) { Text(profile.name); Text("\(profile.username)@\(profile.host) · \(profile.root.description)").font(.caption) }; Spacer(); Button("Edit") { load(profile) }; Button("Test") { coordinator.testRemoteProfile(profile) }; Button("Delete", role: .destructive) { viewModel.deleteRemoteProfile(id: profile.id) } }
                }
            }.frame(height: 130)
            TextField("Name", text: $name); TextField("Host", text: $host); TextField("Port", text: $port); TextField("Username", text: $username); TextField("Relative root", text: $root)
            Picker("Verification", selection: $verification) { Text("SHA-256 read-back").tag(RemoteVerificationMode.sha256); Text("Upload only").tag(RemoteVerificationMode.uploadOnly) }
            Text("Authentication uses your macOS SSH agent. No password, private key, or passphrase is stored or displayed.").font(.caption).foregroundStyle(.secondary)
            Button("Save destination", action: save).disabled(name.isEmpty || host.isEmpty || username.isEmpty)
        }.padding().frame(width: 420)
    }
    private func save() {
        guard let port = Int(port), let relativeRoot = try? RemoteRelativePath(components: root.split(separator: "/").map(String.init)) else { return }
        viewModel.saveRemoteProfile(RemoteDestinationProfile(id: editingID ?? UUID(), name: name, host: host, port: port, username: username, root: relativeRoot, verificationMode: verification))
        name = ""; host = ""; username = ""
        editingID = nil
    }
    private func load(_ profile: RemoteDestinationProfile) { editingID = profile.id; name = profile.name; host = profile.host; port = "\(profile.port)"; username = profile.username; root = profile.root.description; verification = profile.verificationMode }
}
