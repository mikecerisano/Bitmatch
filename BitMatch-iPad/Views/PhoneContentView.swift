// PhoneContentView.swift - Compact iPhone layout reusing shared components
import SwiftUI

struct PhoneContentView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var showSettings = false
    @State private var showingTransfers = false

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
                        TransferAttentionBanner(
                            needsAttentionCount: TransferLibraryPresentation.needsAttentionCount(coordinator.transferJournal.records)
                        ) { showingTransfers = true }
                            .padding(.horizontal)
                        // Tabs
                        AdaptiveModeNavigation(coordinator: coordinator, presentation: .compact)

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
                VStack {
                    NotificationPermissionBanner(coordinator: coordinator)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .navigationTitle("BitMatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingTransfers = true } label: {
                        Label("Transfers", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingTransfers) {
                TransferLibraryView(coordinator: coordinator, journal: coordinator.transferJournal)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheetView(coordinator: coordinator)
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var copyAndVerifyStack: some View {
        if coordinator.isOperationInProgress {
            OperationProgressView(coordinator: coordinator)
        } else if coordinator.showsOutcomeSummary {
            CompletionSummaryView(coordinator: coordinator)
        } else {
            CopyAndVerifyView(coordinator: coordinator)
        }
    }
}
