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
                    selectionView: { presentation in
                        AnyView(HorizontalFlowView(coordinator: coordinator, presentation: presentation))
                    },
                    onStart: start
                )
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
                        Text(fileSelection.sourceURL?.lastPathComponent ?? "Source")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(fileSelection.destinationURLs.count) backup\(fileSelection.destinationURLs.count == 1 ? "" : "s")")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
                }
                Spacer()
                if coordinator.canPause || coordinator.canResume {
                    Button { coordinator.togglePause() } label: {
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
