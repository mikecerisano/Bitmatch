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
    @State private var validationMessage: String?
    @State private var availableWidth: CGFloat = RemoteDestinationLayoutPolicy.twoColumnThreshold

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .foregroundStyle(.tint)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SFTP destinations").font(.headline)
                        Text("Saved destinations can be reused from any project.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showsDoneButton { Button("Done") { dismiss() } }
                }

                if viewModel.remoteProfiles.isEmpty {
                    ContentUnavailableView(
                        "No saved destinations",
                        systemImage: "externaldrive.badge.plus",
                        description: Text("Add an SFTP destination below. BitMatch will use your SSH agent when it connects.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 6) {
                        ForEach(viewModel.remoteProfiles) { profile in
                            destinationRow(profile)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(editingID == nil ? "Add destination" : "Edit destination")
                        .font(.headline)
                    destinationFields
                    field("Relative root", text: $root, prompt: "Backups/2026")
                    Picker("Verification", selection: $verification) {
                        Text("SHA-256 read-back").tag(RemoteVerificationMode.sha256)
                        Text("Upload only").tag(RemoteVerificationMode.uploadOnly)
                    }
                    .pickerStyle(.menu)

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button(editingID == nil ? "Save destination" : "Save changes", action: save)
                            .buttonStyle(.borderedProminent)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if editingID != nil {
                            Button("Cancel", action: clearForm)
                        }
                    }
                }

                Label("Authentication uses your macOS SSH agent. BitMatch never stores or displays your password, private key, or passphrase.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(widthReader)
        }
        .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: editingID)
    }

    @ViewBuilder
    private var destinationFields: some View {
        if RemoteDestinationLayoutPolicy.presentation(for: availableWidth) == .twoColumn {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    field("Name", text: $name, prompt: "Studio archive")
                    field("Host", text: $host, prompt: "backup.example.com")
                }
                GridRow {
                    field("Port", text: $port, prompt: "22")
                    field("Username", text: $username, prompt: "mike")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                field("Name", text: $name, prompt: "Studio archive")
                field("Host", text: $host, prompt: "backup.example.com")
                field("Port", text: $port, prompt: "22")
                field("Username", text: $username, prompt: "mike")
            }
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in availableWidth = width }
        }
    }

    private func destinationRow(_ profile: RemoteDestinationProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.subheadline.weight(.semibold))
                Text("\(profile.username)@\(profile.host) · \(profile.root.description)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(profile.verificationMode == .sha256 ? "SHA-256 read-back" : "Upload only")
                    .font(.caption2)
                    .foregroundStyle(profile.verificationMode == .sha256 ? Color.secondary : Color.orange)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Test connection") { coordinator.testRemoteProfile(profile) }
                Button("Edit") { load(profile) }
                Divider()
                Button("Delete", role: .destructive) {
                    if editingID == profile.id { clearForm() }
                    viewModel.deleteRemoteProfile(id: profile.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.55)))
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, _ in validationMessage = nil }
        }
    }

    private func save() {
        guard let port = Int(port), (1...65_535).contains(port) else {
            validationMessage = "Enter a port from 1 to 65,535."
            return
        }
        guard let relativeRoot = try? RemoteRelativePath(components: root.split(separator: "/").map(String.init)) else {
            validationMessage = "Enter a safe relative folder path."
            return
        }
        viewModel.saveRemoteProfile(RemoteDestinationProfile(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            root: relativeRoot,
            verificationMode: verification
        ))
        clearForm()
    }

    private func load(_ profile: RemoteDestinationProfile) {
        editingID = profile.id
        name = profile.name
        host = profile.host
        port = "\(profile.port)"
        username = profile.username
        root = profile.root.description
        verification = profile.verificationMode
        validationMessage = nil
    }

    private func clearForm() {
        name = ""
        host = ""
        port = "22"
        username = ""
        root = "Backups"
        verification = .sha256
        editingID = nil
        validationMessage = nil
    }
}
