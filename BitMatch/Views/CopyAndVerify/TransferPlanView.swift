import SwiftUI

/// The macOS transfer setup: select the locations, review preflight, then start.
struct TransferPlanView: View {
    @ObservedObject var coordinator: AppCoordinator
    let plan: TransferPlanPresentation
    @Binding var optionsExpanded: Bool
    let selectionView: AnyView
    let onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TransferPlanSourceCard(plan: plan)
                    Image(systemName: "arrow.right").foregroundColor(.white.opacity(0.35))
                    TransferPlanDestinationsCard(plan: plan)
                }
                // This remains the single owner of folder panels and drop validation.
                selectionView
            }
            .padding(.top, 4)

            PhotographerJobSetupView(coordinator: coordinator)
            TransferPlanPreflightCard(plan: plan)
            optionSummary
            TransferOptionsView(coordinator: coordinator, isExpanded: $optionsExpanded)
            actionArea
            if let job = coordinator.photographerJobViewModel.dashboardJob,
               !job.cardIngests.isEmpty {
                PhotographerSessionDashboard(
                    viewModel: coordinator.photographerJobViewModel,
                    job: job,
                    queueRemoteBackup: coordinator.queueRemoteBackup
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private var optionSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(plan.optionSummary, id: \.self) { summary in
                        Text(summary).font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }
            }
            if coordinator.verificationMode == .quick {
                Label("Quick mode does not use checksum verification.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundColor(.orange)
                    .accessibilityLabel("Warning: Quick mode does not use checksum verification")
            }
        }
    }

    private var actionArea: some View {
        let photographerStart = coordinator.photographerJobViewModel.hasPreparedIngestAwaitingStart
            ? coordinator.photographerJobViewModel.startPresentation(
                preflightReady: plan.canStart,
                sourceURL: coordinator.fileSelectionViewModel.sourceURL,
                destinationCount: coordinator.fileSelectionViewModel.destinationURLs.count,
                verificationMode: coordinator.verificationMode
            )
            : nil
        let canStart = photographerStart?.canStart ?? plan.canStart
        return VStack(alignment: .leading, spacing: 8) {
            if let estimate = coordinator.timeEstimate {
                Text("Estimated time: \(estimate.formatted) · \(estimate.speedSummary)")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            } else if coordinator.isCalculatingEstimate {
                Label("Calculating transfer estimate…", systemImage: "clock")
                    .font(.system(size: 11)).foregroundColor(.blue)
            }
            Button(action: onStart) {
                Label(plan.actionTitle, systemImage: "arrow.right.doc.on.clipboard")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundColor(canStart ? .black : .white.opacity(0.45))
            .background(RoundedRectangle(cornerRadius: 10).fill(canStart ? Color.green : Color.white.opacity(0.1)))
            .disabled(!canStart)
            .accessibilityLabel(plan.actionTitle)
            .accessibilityHint(photographerStart?.blocker ?? "Starts the transfer")
            if let disabledReason = photographerStart?.blocker {
                Text(disabledReason).font(.system(size: 11)).foregroundColor(.white.opacity(0.58))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.035)))
    }

}

struct TransferPlanSourceCard: View {
    let plan: TransferPlanPresentation
    var body: some View {
        planCard(title: "SOURCE", icon: "folder.fill", tint: .orange, primary: plan.sourceTitle, detail: plan.sourceDetail)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Source: \(plan.sourceTitle)")
            .accessibilityHint("Choose or drop a source folder below")
    }
}

struct TransferPlanDestinationsCard: View {
    let plan: TransferPlanPresentation
    var body: some View {
        planCard(title: "BACKUPS", icon: "externaldrive.fill", tint: .blue,
                 primary: plan.destinationTitles.isEmpty ? "Add at least one backup" : plan.destinationTitles.joined(separator: ", "),
                 detail: plan.destinationDetail)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Backups: \(plan.destinationDetail)")
            .accessibilityHint("Add, replace, or remove backup destinations below")
    }
}

private func planCard(title: String, icon: String, tint: Color, primary: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Label(title, systemImage: icon).font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(tint)
        Text(primary).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundColor(.white)
        Text(detail).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(11)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
}

struct TransferPlanPreflightCard: View {
    let plan: TransferPlanPresentation
    var body: some View {
        let display = statusDisplay
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: display.icon).foregroundColor(display.tint).font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(display.title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text(display.detail).font(.system(size: 11)).foregroundColor(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(display.tint.opacity(0.1)))
        .accessibilityElement(children: .combine).accessibilityLabel("Preflight: \(display.title). \(display.detail)")
    }
    private var statusDisplay: (title: String, detail: String, icon: String, tint: Color) {
        switch plan.status {
        case .ready: return ("Ready to transfer", "Source and backups are ready.", "checkmark.circle.fill", .green)
        case .analyzing(let message): return ("Analyzing", message, "arrow.triangle.2.circlepath", .blue)
        case .warning(let warnings): return ("Ready with warnings", warnings.first ?? "Review options before starting.", "exclamationmark.triangle.fill", .orange)
        case .blocked(let issues): return ("Blocked", issues.first ?? "Resolve the issue to continue.", "xmark.octagon.fill", .red)
        case .incomplete(let message): return ("Needs setup", message, "info.circle.fill", .orange)
        }
    }
}

struct TransferOptionsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var isExpanded: Bool
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                CameraLabelView(settings: $coordinator.cameraLabelViewModel.destinationLabelSettings,
                                detectedCamera: coordinator.cameraLabelViewModel.detectedCamera,
                                fingerprint: coordinator.cameraLabelViewModel.currentFingerprint,
                                sourceURL: coordinator.fileSelectionViewModel.sourceURL)
                Divider().overlay(Color.white.opacity(0.12))
                Picker("Verification", selection: $coordinator.verificationMode) {
                    ForEach(VerificationMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: coordinator.verificationMode) { _, _ in coordinator.saveVerificationMode() }
                Toggle("Create PDF & CSV Report", isOn: $coordinator.settingsViewModel.prefs.makeReport).tint(.green)
            }.padding(.top, 10)
        } label: {
            HStack {
                Label("Options", systemImage: "slider.horizontal.3")
                Spacer()
                Text("\(coordinator.verificationMode.rawValue) · \(coordinator.settingsViewModel.prefs.makeReport ? "Reports on" : "Reports off")")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
            }.font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.9))
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035)))
        .accessibilityLabel("Options").accessibilityHint("Shows camera labels, verification, and report settings")
    }
}
