import SwiftUI

extension SetupPresentation {
    /// The one adapter from `SharedAppCoordinator`, used by Mac, iPad and
    /// iPhone alike, so every platform shows the same Setup for the same
    /// selection. Readiness is the one shared rule
    /// (`operationReadinessAssessment`); the estimate is the only
    /// platform-supplied value.
    @MainActor
    static func make(coordinator: SharedAppCoordinator, estimateText: String?) -> Self {
        let readiness = coordinator.operationReadinessAssessment
        let plan = TransferPlanPresentation.make(
            sourceURL: coordinator.sourceURL,
            sourceInfo: coordinator.sourceFolderInfo?.asFolderInfo,
            destinationURLs: coordinator.destinationURLs,
            verificationMode: coordinator.verificationMode,
            cameraSettings: coordinator.cameraLabelSettings,
            reportSettings: coordinator.reportSettings,
            isAnalyzing: coordinator.isAnalysingSource,
            blockingIssues: readiness.blockingIssues,
            warnings: readiness.warnings
        )
        let jobs = coordinator.photographerJobViewModel
        let hasPreparedCard = jobs.hasPreparedIngestAwaitingStart
        let projectBlocker: String? = hasPreparedCard
            ? jobs.startPresentation(
                preflightReady: plan.canStart,
                sourceURL: coordinator.sourceURL,
                destinationCount: coordinator.destinationURLs.count,
                verificationMode: coordinator.verificationMode
            ).blocker
            : nil
        return make(
            plan: plan,
            usesProjectWorkflow: coordinator.usesProjectWorkflow,
            hasPreparedCard: hasPreparedCard,
            projectBlocker: projectBlocker,
            projectUnit: jobs.selectedWorkflow.sourceUnitLabel,
            isOperationInProgress: coordinator.isOperationInProgress,
            sourceFileCount: coordinator.sourceFolderInfo?.fileCount,
            sourceBytes: coordinator.sourceFolderInfo?.totalSize,
            destinationCount: coordinator.destinationURLs.count,
            hasProjectEvidence: !(jobs.dashboardJob?.cardIngests.isEmpty ?? true),
            estimateText: estimateText
        )
    }
}

/// `SetupScreen` wired to `SharedAppCoordinator`. Each platform passes only
/// its slots (see `SetupScreen`) and its estimate line.
struct CoordinatorSetupScreen<Locations: View, Problems: View, ProjectSetup: View, LabelContent: View, ProjectEvidence: View>: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var optionsExpanded: Bool
    private let estimateText: String?
    private let locations: (SetupLocationsContext) -> Locations
    private let problems: Problems
    private let projectSetup: ProjectSetup
    private let labelContent: LabelContent
    private let projectEvidence: ProjectEvidence

    init(
        coordinator: SharedAppCoordinator,
        optionsExpanded: Binding<Bool>,
        estimateText: String?,
        @ViewBuilder locations: @escaping (SetupLocationsContext) -> Locations,
        @ViewBuilder problems: () -> Problems,
        @ViewBuilder projectSetup: () -> ProjectSetup,
        @ViewBuilder labelContent: () -> LabelContent,
        @ViewBuilder projectEvidence: () -> ProjectEvidence
    ) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _optionsExpanded = optionsExpanded
        self.estimateText = estimateText
        self.locations = locations
        self.problems = problems()
        self.projectSetup = projectSetup()
        self.labelContent = labelContent()
        self.projectEvidence = projectEvidence()
    }

    var body: some View {
        SetupScreen(
            presentation: .make(coordinator: coordinator, estimateText: estimateText),
            options: SetupOptionsBindings(
                isExpanded: $optionsExpanded,
                verificationMode: $coordinator.verificationMode,
                generateASCMHL: $coordinator.generateASCMHL,
                makeReport: $coordinator.reportSettings.makeReport,
                cameraLabel: coordinator.cameraLabelSettings.label
            ),
            actions: actions,
            locations: locations,
            problems: { problems },
            projectSetup: { projectSetup },
            labelContent: { labelContent },
            projectEvidence: { projectEvidence }
        )
    }

    private var actions: SetupActions {
        let coordinator = self.coordinator
        return SetupActions(
            chooseWorkflow: { workflow in
                coordinator.usesProjectWorkflow = workflow == .project
            },
            start: {
                // The one Start: the same rule as ⌘R, including S-2.
                coordinator.switchMode(to: .copyAndVerify)
                Task { await coordinator.startCurrentMode() }
            }
        )
    }
}
