import SwiftUI

/// The Mac pickers for the shared source and backup boxes
/// (`CoordinatorSetupLocations`): the open panel, drag and drop onto the
/// boxes, and a refusal shown as the drop-rejection toast
/// (`ContentView`, `.dropRejected`). Adds and removals go through
/// `MacVolumeAccessModel`, so a removed drive stays dismissed from
/// discovery and an explicit add clears the dismissal.
///
/// Environment objects: `MacVolumeAccessModel` (from `macCompanions(_:)`).
@MainActor
struct MacSetupLocations: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @EnvironmentObject var volumeAccess: MacVolumeAccessModel
    let context: SetupLocationsContext
    @State private var showingTransfers = false

    var body: some View {
        let volumeAccess = self.volumeAccess
        VStack(spacing: 12) {
            CoordinatorSetupLocations(coordinator: coordinator, context: context, platform: platform)
            MacConnectedDrives(monitor: volumeAccess.volumeMonitor, coordinator: coordinator, platform: platform)
            if coordinator.queuedCardCount > 0 {
                HStack(spacing: 10) {
                    Text("\(coordinator.queuedCardCount) \(coordinator.queuedCardCount == 1 ? "card" : "cards") queued")
                    Spacer()
                    Button("Run queue") { coordinator.startQueue() }
                        .disabled(coordinator.queueIsRunning || coordinator.transferJournal.persistenceError != nil)
                    Button("Show") { showingTransfers = true }
                        .accessibilityLabel("Show queued transfers")
                }
                .font(.subheadline)
                .controlSize(.small)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .sheet(isPresented: $showingTransfers) {
            TransferLibraryView(coordinator: coordinator, journal: coordinator.transferJournal)
        }
    }

    private var platform: SetupLocationsPlatform {
        let volumeAccess = self.volumeAccess
        return SetupLocationsPlatform(
            pickSource: { Self.chooseFolders(multiple: false, prompt: "Choose Source").first },
            pickBackups: { Self.chooseFolders(multiple: true, prompt: "Add Backup") },
            addBackup: { volumeAccess.addDestination($0) },
            removeBackup: { volumeAccess.removeDestination($0) },
            freeSpace: { volumeAccess.formattedAvailableSpace(for: $0) },
            showRefusals: { reasons in
                NotificationCenter.default.post(
                    name: .dropRejected,
                    object: nil,
                    userInfo: ["reason": reasons.joined(separator: "\n")]
                )
            },
            acceptsDrops: true
        )
    }

    /// The open panel, folders only. Empty when cancelled.
    private static func chooseFolders(multiple: Bool, prompt: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = multiple
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
