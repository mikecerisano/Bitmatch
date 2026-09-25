// CompletionSummaryView.swift - the iPad and iPhone outcome
import SwiftUI

/// The shared `OutcomeScreen` for iPad and iPhone (UI plan step 4.7). The
/// Mac shows the same screen; only the shells that route to it differ.
struct CompletionSummaryView: View {
    @ObservedObject var coordinator: SharedAppCoordinator

    var body: some View {
        CoordinatorOutcomeScreen(coordinator: coordinator)
            .frame(maxWidth: 1_100)
            .padding(.horizontal, 20)
    }
}
