// Views/CopyAndVerify/CopyAndVerifyView.swift
import SwiftUI

/// The Mac Copy & Verify setup: the shared Setup screen with the Mac's slots
/// (step 4.8). A running transfer is shown by `MacTransferProgressView`
/// (step 4.9), which `ContentView` selects before this view.
struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var showReportSettings: Bool
    @Binding var optionsExpanded: Bool

    var body: some View {
        MacSetupView(coordinator: coordinator, optionsExpanded: $optionsExpanded)
    }
}
