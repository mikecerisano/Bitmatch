// Views/PreferencesWindow.swift - Dedicated preferences window
import SwiftUI
import AppKit
import BitMatchEngine

struct PreferencesWindow: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let cameraAutoSource: MacCameraAutoSourceController
    let remoteBackups: MacRemoteBackupController
    @Environment(\.dismiss) private var dismiss

    // Tab selection
    @State private var selectedTab: PreferencesTab = .verification

    enum PreferencesTab: String, CaseIterable {
        case verification = "Verification"
        case backups = "Backups"
        case reports = "Reports"
        case cameras = "Cameras"

        var icon: String {
            switch self {
            case .verification: return "checkmark.shield"
            case .backups: return "externaldrive.badge.plus"
            case .reports: return "doc.text"
            case .cameras: return "camera"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case .verification:
                        verificationPreferences
                    case .backups:
                        backupsPreferences
                    case .reports:
                        reportPreferences
                    case .cameras:
                        camerasPreferences
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(20)
            }
        }
        .frame(
            minWidth: PreferencesPresentationPolicy.minimumWidth,
            idealWidth: PreferencesPresentationPolicy.initialWidth,
            maxWidth: .infinity,
            minHeight: PreferencesPresentationPolicy.minimumHeight,
            maxHeight: .infinity
        )
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        // Fixed-size icon well so glyphs of different visual
                        // heights (gear, drive, doc, camera) share one
                        // baseline instead of drifting per-icon.
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))
                            .frame(width: PreferencesPresentationPolicy.tabIconWellSize, height: PreferencesPresentationPolicy.tabIconWellSize)
                        Text(tab.rawValue)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .frame(width: PreferencesPresentationPolicy.tabWidth, height: PreferencesPresentationPolicy.tabHeight)
                    // The bug this fixes: without an explicit shape, only the
                    // glyph and text pixels were tappable, not the tab's
                    // empty margin. contentShape makes the whole frame hit-testable.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    selectedTab == tab ?
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1)) :
                    nil
                )
                // Audit M1: selection was shown by tint color alone.
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Verification

    @ViewBuilder
    private var verificationPreferences: some View {
        Form {
            Section {
                Text("Every backup is checked against your card before BitMatch calls it verified. This sets how thoroughly that check runs.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } header: {
                Text("Verification").font(.title2).fontWeight(.semibold).foregroundColor(.primary)
            }

            Section("Current mode") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(coordinator.verificationMode == .standard ? "Verified copy · SHA-256" : coordinator.verificationMode.rawValue)
                        .font(.headline)
                    Text(coordinator.verificationMode.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if coordinator.verificationMode == .quick {
                        Label("File contents are not checked in Quick mode.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 4)

                DisclosureGroup("Change verification mode") {
                    Picker("Mode", selection: $coordinator.verificationMode) {
                        ForEach(VerificationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .onChange(of: coordinator.verificationMode) { _, _ in coordinator.saveVerificationMode() }
                    .padding(.top, 4)
                }
            }

            Section("Handoff record") {
                ASCMHLPreferenceToggle(shared: coordinator)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Backups

    @ViewBuilder
    private var backupsPreferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backups")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Save an off-site destination here once, then choose it for any project. BitMatch signs in with your Mac's SSH agent and only uploads from a Mac.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            RemoteBackupDestinationManager(
                viewModel: coordinator.photographerJobViewModel,
                remoteBackups: remoteBackups,
                showsDoneButton: false
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Reports

    @ViewBuilder
    private var reportPreferences: some View {
        Form {
            Section {
                Text("A report is a record of what happened during a transfer, saved next to your backups so you can hand it to anyone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } header: {
                Text("Reports").font(.title2).fontWeight(.semibold).foregroundColor(.primary)
            }

            Section {
                Toggle(TransferOptionsPresentation.reportToggleTitle(), isOn: $coordinator.reportSettings.makeReport)
                    .toggleStyle(.checkbox)
            }

            if coordinator.reportSettings.makeReport {
                Section {
                    TextField("Client name", text: $coordinator.reportSettings.clientName)
                    TextField("Project name", text: $coordinator.reportSettings.projectName)
                    TextField("Production title", text: $coordinator.reportSettings.production)
                    TextField("Production company", text: $coordinator.reportSettings.company)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $coordinator.reportSettings.notes)
                            .font(.system(size: 12))
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                } header: {
                    Text("Project details")
                } footer: {
                    Text("These appear on every report until you clear them.")
                }

                Section {
                    Toggle("Include thumbnails", isOn: $coordinator.reportSettings.includeThumbnails)
                        .toggleStyle(.checkbox)
                } footer: {
                    Text("Adds a small preview image for each file to the report.")
                }

                Section {
                    Button("Clear project details") {
                        clearReportMetadata()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut, value: coordinator.reportSettings.makeReport)
    }

    // MARK: - Cameras

    @ViewBuilder
    private var camerasPreferences: some View {
        Form {
            Section {
                Text("BitMatch can notice when a camera card is connected and set it up for you automatically.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } header: {
                Text("Cameras").font(.title2).fontWeight(.semibold).foregroundColor(.primary)
            }

            Section {
                Toggle("Detect camera cards automatically", isOn: $coordinator.reportSettings.enableAutoCameraDetection)
                    .toggleStyle(.checkbox)
                    .onChange(of: coordinator.reportSettings.enableAutoCameraDetection) { oldValue, newValue in
                        cameraAutoSource.toggleCameraDetection(newValue)
                    }
            }

            if coordinator.reportSettings.enableAutoCameraDetection {
                Section("When a card is detected") {
                    Toggle("Set it as the source automatically", isOn: $coordinator.reportSettings.autoPopulateSource)
                        .toggleStyle(.checkbox)
                        .help("When enabled, a detected camera card is set as the source folder for you")

                    Toggle("Show a notification", isOn: $coordinator.reportSettings.showCameraDetectionNotifications)
                        .toggleStyle(.checkbox)
                        .help("Display a system notification when a camera card is detected")
                }

                Section {
                    HStack {
                        Button {
                            cameraAutoSource.rescanForCameras()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Rescan Now")
                            }
                        }
                        .help("Manually scan for connected camera cards")

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Recognized cameras: RED, ARRI, Blackmagic, Sony, Canon, Panasonic, GoPro, DJI, and Fujifilm.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut, value: coordinator.reportSettings.enableAutoCameraDetection)
    }
}

// MARK: - Preferences Window Controller

private extension PreferencesWindow {
    func clearReportMetadata() {
        var prefs = coordinator.reportSettings
        prefs.clientName = ""
        prefs.projectName = ""
        prefs.production = ""
        prefs.company = ""
        prefs.notes = ""
        coordinator.reportSettings = prefs
    }
}

class PreferencesWindowController: NSWindowController {
    convenience init(environment: MacAppEnvironment) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PreferencesPresentationPolicy.initialWidth,
                height: PreferencesPresentationPolicy.initialHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "BitMatch Preferences"
        if PreferencesPresentationPolicy.allowsManualResizing {
            window.styleMask.insert(.resizable)
        }
        window.minSize = NSSize(
            width: PreferencesPresentationPolicy.minimumWidth,
            height: PreferencesPresentationPolicy.minimumHeight
        )
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
        window.contentView = NSHostingView(rootView: PreferencesWindow(
            coordinator: environment.coordinator,
            cameraAutoSource: environment.cameraAutoSource,
            remoteBackups: environment.remoteBackups
        ))

        self.init(window: window)
    }
}

#if DEBUG
struct PreferencesWindow_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let persistence = BitMatchPersistenceController(inMemory: true)
        let store = CoreDataPhotographerJobStore(persistence: persistence)
        let environment = MacAppEnvironment.makeForTesting(coordinator: SharedAppCoordinator(
            platformManager: MacOSPlatformManager.shared,
            photographerJobViewModel: PhotographerJobViewModel(store: store)
        ))
        return PreferencesWindow(
            coordinator: environment.coordinator,
            cameraAutoSource: environment.cameraAutoSource,
            remoteBackups: environment.remoteBackups
        )
    }
}
#endif

/// The same ASC MHL setting iOS Settings shows, bound to the shared coordinator.
private struct ASCMHLPreferenceToggle: View {
    @ObservedObject var shared: SharedAppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("ASC MHL handoff record", isOn: $shared.generateASCMHL)
                .toggleStyle(.checkbox)
                .disabled(!TransferOptionsPresentation.ascMHLEnabled(for: shared.verificationMode))
            Text(TransferOptionsPresentation.ascMHLFootnote(for: shared.verificationMode))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
