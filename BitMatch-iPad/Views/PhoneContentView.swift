// PhoneContentView.swift - Compact iPhone layout reusing shared components
import SwiftUI

struct PhoneContentView: View {
    @StateObject private var coordinator = SharedAppCoordinator()
    @State private var cameraLabelExpanded = false
    @State private var verificationModeExpanded = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.05),
                        Color(red: 0.1, green: 0.1, blue: 0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Tabs
                        HeaderTabsView(coordinator: coordinator)

                        switch coordinator.currentMode {
                        case .copyAndVerify:
                            copyAndVerifyStack
                        case .compareFolders:
                            // Reuse iPad Compare component in a phone-friendly stack
                            CompareFoldersView(coordinator: coordinator)
                                .padding(.horizontal, 16)
                        case .masterReport:
                            MasterReportView(coordinator: coordinator)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheetView(coordinator: coordinator)
            }
            .preferredColorScheme(.dark)
        }
    }

    private var copyAndVerifyStack: some View {
        VStack(spacing: 14) {
            // Stacked cards for phone
            VStack(spacing: 12) {
                ProfessionalSourceCard(coordinator: coordinator)
                DestinationsFlowView(coordinator: coordinator)
            }
            .padding(.horizontal, 16)

            CollapsibleLabelingSection(coordinator: coordinator, isExpanded: $cameraLabelExpanded)
                .padding(.horizontal, 16)
            CollapsibleVerificationSection(coordinator: coordinator, isExpanded: $verificationModeExpanded)
                .padding(.horizontal, 16)
            ReportToggleCard(coordinator: coordinator)
                .padding(.horizontal, 16)

            if coordinator.isOperationInProgress {
                OperationProgressView(coordinator: coordinator)
                    .padding(.horizontal, 16)
            }

            StartTransferButtonView(coordinator: coordinator)
                .padding(.horizontal, 16)
        }
    }
}

