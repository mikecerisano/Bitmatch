import SwiftUI

extension TransferOutcomePresentation {
    /// The one adapter from `SharedAppCoordinator`, used by Mac, iPad and
    /// iPhone alike, so every platform shows the same outcome for the same run.
    @MainActor
    static func make(coordinator: SharedAppCoordinator) -> Self {
        let record = coordinator.outcomeRecord
        let duration: TimeInterval? = record.flatMap { record in
            guard let started = record.startedAt, let ended = record.endedAt else { return nil }
            return ended.timeIntervalSince(started)
        }
        let isFinished = record.map { $0.state != .queued && $0.state != .running } ?? false
        return make(
            state: coordinator.operationState,
            rows: coordinator.results,
            destinations: coordinator.destinationURLs,
            hasErrors: coordinator.hasErrors,
            hasCriticalErrors: coordinator.hasCriticalErrors,
            errorCount: coordinator.errorCount,
            warningCount: coordinator.warningCount,
            duration: duration,
            verificationMode: record?.verificationMode,
            canRetry: isFinished && record?.canRetry == true,
            canExport: isFinished
        )
    }
}

/// `OutcomeScreen` wired to `SharedAppCoordinator`. The Mac passes its
/// project dashboard (with SFTP actions) as `projectEvidence`; iPad and
/// iPhone pass nothing.
struct CoordinatorOutcomeScreen<ProjectEvidence: View>: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    private let onNewTransfer: () -> Void
    private let projectEvidence: ProjectEvidence
    @State private var retryRequested = false

    init(
        coordinator: SharedAppCoordinator,
        onNewTransfer: @escaping () -> Void = {},
        @ViewBuilder projectEvidence: () -> ProjectEvidence
    ) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        self.onNewTransfer = onNewTransfer
        self.projectEvidence = projectEvidence()
    }

    var body: some View {
        let presentation = TransferOutcomePresentation.make(coordinator: coordinator)
        OutcomeScreen(
            presentation: presentation,
            rows: coordinator.results,
            // Only the answer to this screen's own Retry; older queue
            // messages belong to Transfers.
            notice: retryRequested ? coordinator.queueMessage : nil,
            isBusy: coordinator.isOperationInProgress,
            actions: actions(for: presentation),
            projectEvidence: { projectEvidence }
        )
    }

    private func actions(for presentation: TransferOutcomePresentation) -> OutcomeActions {
        let coordinator = self.coordinator
        var retry: (() -> Void)?
        if presentation.canRetry, let recordID = coordinator.outcomeRecord?.id {
            retry = {
                retryRequested = true
                coordinator.retryTransfer(recordID)
            }
        }
        var export: ((Bool) throws -> TransferHistoryDocument)?
        if presentation.canExport {
            export = { asCSV in try coordinator.completionExportDocument(asCSV: asCSV) }
        }
        return OutcomeActions(
            newTransfer: {
                retryRequested = false
                coordinator.startNewTransfer()
                onNewTransfer()
            },
            retry: retry,
            export: export
        )
    }
}

extension CoordinatorOutcomeScreen where ProjectEvidence == EmptyView {
    init(coordinator: SharedAppCoordinator, onNewTransfer: @escaping () -> Void = {}) {
        self.init(coordinator: coordinator, onNewTransfer: onNewTransfer) { EmptyView() }
    }
}
