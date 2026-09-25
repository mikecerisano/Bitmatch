// Views/CopyAndVerify/CopyAndVerifyView.swift
import SwiftUI

struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @EnvironmentObject var remoteBackups: MacRemoteBackupController
    @Binding var showReportSettings: Bool
    @Binding var optionsExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if coordinator.isOperationInProgress {
                compactOperationView
            } else {
                // The shared Setup screen with the Mac's slots (step 4.8).
                MacSetupView(coordinator: coordinator, optionsExpanded: $optionsExpanded)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.84), value: coordinator.isOperationInProgress)
    }

    private var compactOperationView: some View {
        let presentation = TransferOperationPresentation.make(
            state: coordinator.operationState,
            isPaused: coordinator.isPaused
        )
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(coordinator.isPaused ? .orange : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(coordinator.sourceURL?.lastPathComponent ?? "Source")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(coordinator.destinationURLs.count) backup\(coordinator.destinationURLs.count == 1 ? "" : "s")")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
                }
                Spacer()
                if coordinator.canPause || coordinator.canResume {
                    Button { Task { await coordinator.togglePause() } } label: {
                        Label(presentation.controlTitle, systemImage: presentation.controlSymbol)
                    }
                    .buttonStyle(CustomButtonStyle())
                    .accessibilityHint(coordinator.isPaused ? "Resumes the current transfer" : "Pauses the current transfer")
                    .help("\(presentation.controlTitle) transfer")
                }
                Button { coordinator.cancelOperation() } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                    .buttonStyle(CustomButtonStyle(isDestructive: true))
                    .accessibilityLabel("Cancel transfer")
            }
            .padding(14)
            .background(Color.white.opacity(0.035))
            TransferQueueView(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let job = coordinator.photographerJobViewModel.dashboardJob,
               !job.cardIngests.isEmpty {
                PhotographerSessionDashboard(
                    viewModel: coordinator.photographerJobViewModel,
                    job: job,
                    queueRemoteBackup: remoteBackups.queueRemoteBackup,
                    retryRemoteBackup: remoteBackups.retryRemoteBackup,
                    cancelRemoteBackup: remoteBackups.cancelRemoteBackup
                )
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
    }
}
