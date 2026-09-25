import SwiftUI

/// The Mac's slots for the shared Setup screen (UI plan step 4.8): drag and
/// drop with drive discovery for the locations, the unreadable-card banner,
/// project setup with presets and SFTP, the camera label editor, the project
/// dashboard, and the drive-benchmark estimate. Everything else, including
/// readiness and the Start button, is the screen iPad and iPhone show.
///
/// Environment objects: `MacVolumeAccessModel` (read by `HorizontalFlowView`),
/// `MacRemoteBackupController` and `TransferEstimateModel`. All three come
/// from `macCompanions(_:)` on the window root.
struct MacSetupView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @EnvironmentObject var remoteBackups: MacRemoteBackupController
    @EnvironmentObject var estimate: TransferEstimateModel
    @Binding var optionsExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CoordinatorSetupScreen(
            coordinator: coordinator,
            optionsExpanded: $optionsExpanded,
            estimateText: estimateText
        ) { context in
            // The single owner of folder panels, drop validation and
            // discovered drives.
            HorizontalFlowView(
                coordinator: coordinator,
                presentation: context.layout == .compact ? .compact : .expanded,
                nextStep: context.nextStep
            )
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
            )
        } problems: {
            // A card macOS cannot read is a real, actionable problem.
            UnreadableMediaBanner()
        } projectSetup: {
            PhotographerJobSetupView(coordinator: coordinator)
        } labelContent: {
            MacCameraLabelSlot(coordinator: coordinator, cameraLabels: coordinator.cameraLabels)
        } projectEvidence: {
            if let job = coordinator.photographerJobViewModel.dashboardJob {
                PhotographerSessionDashboard(
                    viewModel: coordinator.photographerJobViewModel,
                    job: job,
                    queueRemoteBackup: remoteBackups.queueRemoteBackup,
                    retryRemoteBackup: remoteBackups.retryRemoteBackup,
                    cancelRemoteBackup: remoteBackups.cancelRemoteBackup
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    /// The drive-benchmark estimate (Mac only until the engine estimates
    /// from observed copy speed; thesis, step 5).
    private var estimateText: String? {
        if let timeEstimate = estimate.estimate {
            return "Estimated time: \(timeEstimate.formatted) · \(timeEstimate.speedSummary)"
        }
        if estimate.isCalculating {
            return "Calculating transfer estimate…"
        }
        return nil
    }
}

/// The camera label editor inside Advanced. It observes the label model
/// directly, so edits and the detected camera stay current.
private struct MacCameraLabelSlot: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @ObservedObject var cameraLabels: CameraLabelModel

    var body: some View {
        CameraLabelView(
            settings: $cameraLabels.settings,
            detectedCamera: cameraLabels.detectedCamera,
            fingerprint: cameraLabels.currentFingerprint,
            sourceURL: coordinator.sourceURL
        )
    }
}
