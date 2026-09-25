// OperationProgressView.swift - iPad and iPhone adapter over the shared ProgressScreen
import SwiftUI

/// The transfer progress on iPad and iPhone: the shared `ProgressScreen`
/// (UI plan step 4.9), the same screen and rules as the Mac. The shells keep
/// calling this name, so their routing is unchanged.
///
/// The coordinator is passed, not observed: live progress is observed inside
/// `CoordinatorProgressScreen`, so neither this view nor the shell above it
/// redraws on each progress tick.
struct OperationProgressView: View {
    let coordinator: SharedAppCoordinator
    @State private var confirmingCancel = false

    var body: some View {
        CoordinatorProgressScreen(coordinator: coordinator, confirmingCancel: $confirmingCancel)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
    }
}
