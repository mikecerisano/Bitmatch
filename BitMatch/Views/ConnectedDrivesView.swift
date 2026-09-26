import SwiftUI

struct ConnectedDrivesView: View {
    let rows: [ConnectedDrivesPresentation.Row]
    let useAsCard: (URL) -> Void
    let addAsBackup: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected drives")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if rows.isEmpty {
                Text("Connect a card or drive to see it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.role == .card ? "sdcard" : "externaldrive")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(row.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        switch row.state {
                        case .isSource:
                            Label("Card", systemImage: "checkmark")
                                .foregroundStyle(.secondary)
                        case .isBackup:
                            Label("Backup", systemImage: "checkmark")
                                .foregroundStyle(.secondary)
                        case .none:
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) { buttons(for: row) }
                                VStack(alignment: .trailing, spacing: 4) { buttons(for: row) }
                            }
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(row.displayName)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func buttons(for row: ConnectedDrivesPresentation.Row) -> some View {
        Button("Use as card") { useAsCard(row.url) }
            .accessibilityLabel("Use \(row.displayName) as card")
        Button("Add as backup") { addAsBackup(row.url) }
            .accessibilityLabel("Add \(row.displayName) as backup")
    }
}

@MainActor
struct MacConnectedDrives: View {
    @ObservedObject var monitor: VolumeMonitorService
    @ObservedObject var coordinator: SharedAppCoordinator
    let platform: SetupLocationsPlatform

    var body: some View {
        let selection = SetupLocationSelection(
            coordinator: coordinator,
            addBackup: platform.addBackup,
            removeBackup: platform.removeBackup
        )
        ConnectedDrivesView(
            rows: ConnectedDrivesPresentation.make(
                volumes: monitor.connectedVolumes,
                sourceURL: coordinator.sourceURL?.standardizedFileURL.resolvingSymlinksInPath(),
                destinationURLs: coordinator.destinationURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            ),
            useAsCard: { show(selection.chooseSource($0)) },
            addAsBackup: { show(selection.addBackups([$0])) }
        )
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(coordinator.isOperationInProgress)
    }

    private func show(_ refusals: [String]) {
        if !refusals.isEmpty { platform.showRefusals(refusals) }
    }
}

@MainActor
struct MacQueueNextCards: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @ObservedObject var monitor: VolumeMonitorService

    var body: some View {
        let rows = coordinator.queueCandidates(volumes: monitor.connectedVolumes)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    Button("Queue \(row.displayName) next") {
                        do { try coordinator.enqueueNext(source: row.url) }
                        catch { Task { await coordinator.showError(error) } }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
