import SwiftUI

struct PhotographerSessionDashboard: View {
    @ObservedObject var viewModel: PhotographerJobViewModel
    let job: PhotographerJob
    let queueRemoteBackup: (UUID) -> Void
    let retryRemoteBackup: (UUID) -> Void
    let cancelRemoteBackup: (UUID) -> Void
    @AccessibilityFocusState private var accessibilityFocusedCardID: UUID?
    @FocusState private var keyboardFocusedCardID: UUID?

    private var presentation: PhotographerSessionPresentation {
        PhotographerSessionPresentation.make(job: job)
    }

    var body: some View {
        if !presentation.rows.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Project media")
                        .font(DesignSystem.Typography.heading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Text(presentation.requiredCopyTitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.xs) {
                            ForEach(presentation.rows) { row in
                                cardRow(row)
                                    .id(row.id)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                    .onChange(of: viewModel.focusedCardIngestID) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                        keyboardFocusedCardID = id
                        accessibilityFocusedCardID = id
                    }
                    .onAppear {
                        if let id = viewModel.focusedCardIngestID {
                            proxy.scrollTo(id, anchor: .center)
                            keyboardFocusedCardID = id
                            accessibilityFocusedCardID = id
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(presentation.title). \(presentation.requiredCopyTitle)")
        }
    }

    private func cardRow(_ row: PhotographerCardRowPresentation) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: row.statusSymbol)
                .foregroundColor(row.status.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(row.photographerName).font(DesignSystem.Typography.body)
                    Text("· \(row.cameraName) · \(sourceUnitTitle(row.cardTitle))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text(row.statusTitle)
                        .font(DesignSystem.Typography.micro)
                        .foregroundColor(row.status.color)
                }
                Text("\(row.fileCountTitle) · \(row.byteCountTitle) · \(row.verifiedCopyTitle)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text(row.renderedPath)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if row.statusTitle == "Locally Safe", job.remoteBackupConfiguration?.isEnabled == true {
                    Button("Queue off-site backup") { queueRemoteBackup(row.id) }
                        .font(DesignSystem.Typography.caption)
                        .disabled(job.remoteBackupConfiguration?.destinationProfileID == nil)
                }
                ForEach(row.remoteBackupPresentations.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                    if let remote = row.remoteBackupPresentations[id] {
                        Label(remote.title, systemImage: remote.symbol)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(
                                // Audit M11: "Remote Failed" is an error, not
                                // the same orange as "retrying"/"unverified".
                                remote.isError ? DesignSystem.Colors.error
                                    : remote.isWarning ? DesignSystem.Colors.warning
                                    : (remote.isFullyBackedUp ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                            )
                    }
                }
                let remoteStates = Set(row.remoteBackupPresentations.values.map(\.state))
                if remoteStates.contains(where: { [.paused, .retrying, .failed].contains($0) }) {
                    Button("Retry off-site backup") { retryRemoteBackup(row.id) }
                        .font(DesignSystem.Typography.caption)
                }
                if remoteStates.contains(where: { [.queued, .uploading, .retrying, .verifying].contains($0) }) {
                    Button("Cancel off-site backup") { cancelRemoteBackup(row.id) }
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.error)
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(viewModel.focusedCardIngestID == row.id
                    ? DesignSystem.Colors.surfaceActive
                    : DesignSystem.Colors.background.opacity(0.22))
        )
        .accessibilityElement(children: .combine)
        .focusable()
        .focused($keyboardFocusedCardID, equals: row.id)
        .accessibilityFocused($accessibilityFocusedCardID, equals: row.id)
        .accessibilityLabel("\(row.photographerName), \(row.cameraName), \(row.cardTitle), \(row.fileCountTitle), \(row.byteCountTitle), \(row.statusTitle), \(row.verifiedCopyTitle), package route \(row.renderedPath), \(row.remoteBackupPresentations.values.map(\.title).joined(separator: ", "))")
    }

    private func sourceUnitTitle(_ cardTitle: String) -> String {
        switch job.workflow {
        case .photography:
            cardTitle
        case .videoDIT:
            cardTitle.replacingOccurrences(of: "Card", with: "Media")
        case .general:
            cardTitle.replacingOccurrences(of: "Card", with: "Package")
        }
    }
}
