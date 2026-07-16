// Views/CopyAndVerify/CopyAndVerifyView.swift
import SwiftUI

struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var showReportSettings: Bool
    @Binding var optionsExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fileSelection: FileSelectionViewModel { coordinator.fileSelectionViewModel }
    private var plan: TransferPlanPresentation {
        TransferPlanPresentation.make(
            sourceURL: fileSelection.sourceURL,
            sourceInfo: fileSelection.sourceFolderInfo,
            destinationURLs: fileSelection.destinationURLs,
            verificationMode: coordinator.verificationMode,
            cameraSettings: coordinator.cameraLabelViewModel.destinationLabelSettings,
            reportSettings: coordinator.settingsViewModel.prefs,
            isAnalyzing: fileSelection.isFetchingSourceInfo,
            blockingIssues: readinessIssues,
            warnings: readinessWarnings
        )
    }

    /// Keeps validation policy in the existing validator while supplying its results
    /// to the presentation model.
    private var readinessIssues: [String] {
        guard let sourceURL = fileSelection.sourceURL else {
            return fileSelection.destinationURLs.isEmpty ? [] : ["Select a source folder"]
        }

        var issues: [String] = []
        if fileSelection.destinationURLs.isEmpty { issues.append("Add at least one destination") }

        let uniquePaths = Set(fileSelection.destinationURLs.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        if uniquePaths.count != fileSelection.destinationURLs.count {
            issues.append("Remove duplicate destinations")
        }

        for destination in fileSelection.destinationURLs {
            if SafetyValidator.isProtectedSystemPath(destination) {
                issues.append("\(destination.lastPathComponent) is a system folder")
            } else if let issue = SafetyValidator.destinationSafetyIssue(source: sourceURL, destination: destination) {
                issues.append("\(destination.lastPathComponent): \(issue)")
            } else if let sourceSize = fileSelection.sourceFolderInfo?.totalSize,
                      let available = availableSpace(for: destination),
                      available < sourceSize + Int64(100 * 1024 * 1024) {
                issues.append("Not enough space on \(destination.lastPathComponent)")
            }
        }

        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: sourceURL,
                destinations: fileSelection.destinationURLs,
                settings: coordinator.cameraLabelViewModel.destinationLabelSettings
            )
        } catch {
            issues.append(error.localizedDescription)
        }
        return issues
    }

    private var readinessWarnings: [String] {
        var warnings: [String] = []
        if coordinator.verificationMode == .quick {
            warnings.append("Quick mode only checks file size. Standard SHA-256 is safer for production transfers.")
        }
        if let sourceSize = fileSelection.sourceFolderInfo?.totalSize {
            warnings.append(contentsOf: fileSelection.destinationURLs.compactMap { destination in
                guard let available = availableSpace(for: destination), available > 0 else { return nil }
                return Double(sourceSize) / Double(available) > 0.7
                    ? "Limited space on \(destination.lastPathComponent)" : nil
            })
        }
        return warnings
    }

    var body: some View {
        Group {
            if coordinator.isOperationInProgress {
                compactOperationView
            } else {
                TransferPlanView(
                    coordinator: coordinator,
                    plan: plan,
                    optionsExpanded: $optionsExpanded,
                    selectionView: AnyView(HorizontalFlowView(coordinator: coordinator)),
                    onStart: start
                )
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.84), value: coordinator.isOperationInProgress)
    }

    private var compactOperationView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(fileSelection.sourceURL?.lastPathComponent ?? "Source", systemImage: "folder.fill")
                    .foregroundColor(.orange)
                Image(systemName: "arrow.right").foregroundColor(.white.opacity(0.5))
                Label("\(fileSelection.destinationURLs.count) destinations", systemImage: "externaldrive.fill")
                    .foregroundColor(.blue)
                Spacer()
                if coordinator.canPause || coordinator.canResume {
                    Button { coordinator.togglePause() } label: {
                        Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(coordinator.isPaused ? .green : .white.opacity(0.8))
                    .accessibilityLabel(coordinator.isPaused ? "Resume transfer" : "Pause transfer")
                    .accessibilityHint(coordinator.isPaused ? "Resumes the current transfer" : "Pauses the current transfer")
                    .help(coordinator.isPaused ? "Resume transfer" : "Pause transfer")
                }
                Button { coordinator.cancelOperation() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundColor(.red)
                    .accessibilityLabel("Cancel transfer")
            }
            .font(.system(size: 12, weight: .medium))
            .padding(14)
            .background(Color.black.opacity(0.3))
            TransferQueueView(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let job = coordinator.photographerJobViewModel.dashboardJob,
               !job.cardIngests.isEmpty {
                PhotographerSessionDashboard(
                    viewModel: coordinator.photographerJobViewModel,
                    job: job,
                    queueRemoteBackup: coordinator.queueRemoteBackup
                )
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
    }

    private func start() {
        coordinator.switchMode(to: .copyAndVerify)
        coordinator.startOperation()
    }

    private func availableSpace(for url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
}
