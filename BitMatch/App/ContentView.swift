// App/ContentView.swift - the Mac window
import SwiftUI
import AppKit

/// Owns the Mac app's state for the window's lifetime and hands it to
/// `MacMainView`, which observes each object directly.
struct ContentView: View {
    @StateObject private var environment: MacAppEnvironment

    init(environment: MacAppEnvironment? = nil) {
        _environment = StateObject(wrappedValue: environment ?? MacAppEnvironment.make())
    }

    var body: some View {
        MacMainView(
            environment: environment,
            coordinator: environment.coordinator,
            remoteBackups: environment.remoteBackups
        )
        .macCompanions(environment)
    }
}

struct MacMainView: View {
    let environment: MacAppEnvironment
    @ObservedObject var coordinator: SharedAppCoordinator
    @ObservedObject var remoteBackups: MacRemoteBackupController
    @ObservedObject private var errorHandler = GlobalErrorHandler.shared
#if DEBUG
    @ObservedObject private var devModeManager = DevModeManager.shared
#endif
    @State private var showingTransfers = false
    @State private var showOnlyIssues = false
    
    // Keep an active transfer visually stable while its queue grows.
    @State private var contentHeight: CGFloat = 900
    @State private var isOperationActive = false
    @State private var lockHeight = false
    
    // Preferences window management
    @State private var preferencesWindowController: PreferencesWindowController?
    
    // Dynamic window height management
    @State private var transferOptionsExpanded = false
    @State private var verificationModeExpanded = false
    @State private var showCancelNotice = false
    @State private var showDropRejection = false
    @State private var dropRejectionMessage = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    
    // Calculate ideal window height based on content and current mode
    private var idealWindowHeight: CGFloat {
        let baseHeight: CGFloat = 200  // Header + margins
        
        var totalHeight = baseHeight
        
        // Add content height based on current mode
        switch coordinator.currentMode {
        case .copyAndVerify:
            // Allow room for the source row, backup grid, and primary action.
            // Backup rows grow in pairs at the default compact window width.
            let destinationCount = coordinator.destinationURLs.count
            let hasSource = coordinator.sourceURL != nil
            let extraRows = max(0, (destinationCount + 1) / 2 - 1)
            let locationsHeight: CGFloat = hasSource ? 320 + CGFloat(extraRows) * 84 : 230
            totalHeight += locationsHeight + 200

            if transferOptionsExpanded { totalHeight += 330 }
            
        case .compareFolders:
            // CompareScreen: title, the two folder slots, then checks and the
            // Compare button. Results scroll below; the window is not grown for them.
            let headerHeight: CGFloat = 60
            let foldersHeight: CGFloat = 170
            let actionsHeight: CGFloat = 170
            totalHeight += headerHeight + foldersHeight + actionsHeight

            if verificationModeExpanded {
                totalHeight += 150  // Advanced: verification picker
            }
            
        case .masterReport:
            let reportContentHeight: CGFloat = 300  // Master report centered content area
            totalHeight += reportContentHeight
        }
        
        // Get screen height and leave room for menu bar + dock
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxAllowedHeight = screenHeight - 100  // Leave 100px for system UI
        
        return min(totalHeight, maxAllowedHeight)
    }
    
    /// BitMatch opens as a compact instrument. From that point, the person owns the width.
    private let compactWindowWidth: CGFloat = 680

    var body: some View {
        configuredMainContentView
    }
    
    @ViewBuilder
    private var configuredMainContentView: some View {
        keyboardShortcutsView
            .sheet(isPresented: $showingTransfers) {
                TransferLibraryView(coordinator: coordinator, journal: coordinator.transferJournal)
            }
            .onAppear {
                restoreWindowFrame()
                updateWindowSize(width: compactWindowWidth, height: idealWindowHeight)

            }
            .alert("Error", isPresented: $errorHandler.showErrorAlert) {
                if errorHandler.currentError?.canRetry == true {
                    Button("Retry") {
                        errorHandler.retry()
                    }
                }
                Button("OK", role: .cancel) {
                    errorHandler.clearError()
                }
            } message: {
                let description = errorHandler.currentError?.localizedDescription ?? "An unknown error occurred"
                let recovery = errorHandler.currentError?.recoverySuggestion
                if let recovery {
                    Text("\(description)\n\n\(recovery)")
                } else {
                    Text(description)
                }
            }
            .alert("Confirm SFTP Host Key", isPresented: Binding(get: { remoteBackups.hostTrustPrompt != nil }, set: { if !$0 { remoteBackups.confirmHostTrust(false) } })) {
                Button("Trust Host Key") { remoteBackups.confirmHostTrust(true) }
                Button("Cancel", role: .cancel) { remoteBackups.confirmHostTrust(false) }
            } message: {
                if let prompt = remoteBackups.hostTrustPrompt {
                    Text("Verify this SHA-256 fingerprint for \(prompt.request.host):\(prompt.request.port) before continuing with SSH-agent authentication:\n\n\(prompt.request.sha256Fingerprint)")
                }
            }
    }
    
    @ViewBuilder
    private var styledMainContentView: some View {
        mainContentView
            .preferredColorScheme(.dark)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: coordinator.completionState)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: coordinator.isOperationInProgress)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), value: coordinator.currentMode)
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        ZStack {
            mainContentArea
            // Lightweight toast overlays
            VStack {
                if showCancelNotice {
                    ToastView(
                        icon: "xmark.circle",
                        message: coordinator.currentMode == .compareFolders ? "Compare cancelled" : "Transfer cancelled",
                        tint: .red
                    )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showDropRejection {
                    ToastView(icon: "exclamationmark.triangle", message: dropRejectionMessage, tint: .orange)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 16)
        }
    }
    
    @ViewBuilder
    private var mainContentArea: some View {
        VStack(spacing: 0) {
            headerView
            TransferAttentionBanner(
                needsAttentionCount: TransferLibraryPresentation.needsAttentionCount(coordinator.transferJournal.records)
            ) { showingTransfers = true }
                .padding(.bottom, 8)
            mainScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(darkBackground)
    }
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                mainContentSwitch
                resultsArea
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxHeight: lockHeight ? contentHeight : 900)
    }
    
    @ViewBuilder
    private var mainContentSwitch: some View {
        // Compare shows its own progress and outcome inside CompareScreen, and
        // a finished compare is never shown as the transfer completion.
        if coordinator.currentMode == .compareFolders || coordinator.lastOperationWasCompare {
            modeSpecificView
                .padding(.top, 16)
        } else {
            transferContentSwitch
        }
    }

    @ViewBuilder
    private var transferContentSwitch: some View {
        switch coordinator.completionState {
        case .idle, .inProgress:
            // While in progress, keep showing the active mode's view.
            // Copy & Verify view renders its compact progress UI when in progress.
            modeSpecificView
                .padding(.top, 16)
        default:
            completionView
        }
    }
    
    @ViewBuilder
    private var resultsArea: some View {
        // Live results while a transfer runs; the outcome screen lists them after.
        if coordinator.currentMode == .copyAndVerify &&
           !coordinator.lastOperationWasCompare &&
           coordinator.isOperationInProgress {
            ResultsTableView(
                coordinator: coordinator,
                showOnlyIssues: $showOnlyIssues
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - View Components
    @ViewBuilder
    private var headerView: some View {
        GeometryReader { proxy in
            HStack(spacing: 12) {
                Text("BitMatch")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 8)
                // Decision C-2: no mode switch while anything runs.
                if !isModeSwitchLocked {
                    if HeaderPresentationPolicy.presentation(for: proxy.size.width) == .expanded {
                        ModeSelectorView(mode: $coordinator.currentMode)
                            .transition(.opacity)
                    } else {
                        CompactModeSelectorView(mode: $coordinator.currentMode)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 8)
                Button { showingTransfers = true } label: {
                    Image(systemName: "clock.arrow.circlepath").frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Transfers and history")
                .help("Transfers and history")
                Button {
                    openPreferences()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 68)
        .background(Color.black.opacity(0.4))
    }
    
    @ViewBuilder
    private var modeSpecificView: some View {
        Group {
            switch coordinator.currentMode {
            case .copyAndVerify:
                CopyAndVerifyView(
                    coordinator: coordinator,
                    showReportSettings: .constant(false),
                    optionsExpanded: $transferOptionsExpanded
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .scale(scale: 1.02))
                ))
                
            case .compareFolders:
                CompareFoldersView(
                    coordinator: coordinator,
                    advancedExpanded: $verificationModeExpanded
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .scale(scale: 1.02))
                ))
                
            case .masterReport:
                MasterReportView(coordinator: coordinator)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))
                    ))
            }
        }
    }
    
    /// The shared outcome screen (UI plan step 4.7), with the Mac's project
    /// dashboard and its SFTP actions in the evidence slot.
    @ViewBuilder
    private var completionView: some View {
        CoordinatorOutcomeScreen(coordinator: coordinator, onNewTransfer: {
            lockHeight = false
            isOperationActive = false
        }) {
            if let job = coordinator.photographerJobViewModel.dashboardJob,
               CompletionEvidencePresentation.shouldShowProjectMedia(
                hasDashboardJob: true,
                hasCardIngests: !job.cardIngests.isEmpty
               ) {
                PhotographerSessionDashboard(
                    viewModel: coordinator.photographerJobViewModel,
                    job: job,
                    queueRemoteBackup: remoteBackups.queueRemoteBackup,
                    retryRemoteBackup: remoteBackups.retryRemoteBackup,
                    cancelRemoteBackup: remoteBackups.cancelRemoteBackup
                )
            }
        }
        .padding(.top, 16)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 1.05).combined(with: .opacity)
        ))
    }
    
    private var darkBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.11, blue: 0.12),
                    Color(red: 0.07, green: 0.07, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Preferences Management
    
    private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(environment: environment)
        }
        
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Helpers

    private var isModeSwitchLocked: Bool {
        ModeSwitchPolicy.isLocked(
            isOperationInProgress: coordinator.isOperationInProgress,
            queueIsRunning: coordinator.queueIsRunning
        )
    }

    private func handleOperationStateChange(oldValue: Bool, newValue: Bool) {
        if newValue && !lockHeight {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                if let window = NSApplication.shared.windows.first {
                    contentHeight = window.contentView?.bounds.height ?? 700
                }
            }
            lockHeight = true
            isOperationActive = true
        } else if !newValue && isOperationActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                lockHeight = false
                isOperationActive = false
            }
        }
    }
    
    // MARK: - Completion State Helpers
    private var completionMessage: String {
        switch coordinator.completionState {
        case .success(let msg): return msg
        case .issues(let msg): return msg
        case .failed(let msg): return msg
        case .cancelled(let msg): return msg
        case .idle: return ""
        case .inProgress: return ""
        }
    }

    private var completionIcon: String {
        switch coordinator.completionState {
        case .success: return "checkmark.circle.fill"
        case .issues: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .idle: return ""
        case .inProgress: return "clock.fill"
        }
    }

    private var completionColor: Color {
        switch coordinator.completionState {
        case .success: return .green
        case .issues: return .yellow
        case .failed: return .red
        case .cancelled: return .gray
        case .idle: return .gray
        case .inProgress: return .blue
        }
    }
    
    private func updateWindowHeight(to newHeight: CGFloat) {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                let currentFrame = window.frame
                let newFrame = NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y + (currentFrame.height - newHeight),
                    width: currentFrame.width,
                    height: newHeight
                )
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(newFrame, display: true)
                }
                saveWindowFrame(newFrame)
            }
        }
    }

    private func updateWindowSize(width: CGFloat, height: CGFloat) {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                let currentFrame = window.frame
                let newFrame = NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y + (currentFrame.height - height),
                    width: width,
                    height: height
                )

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(newFrame, display: true)
                }
                saveWindowFrame(newFrame)
            }
        }
    }

    private func saveWindowFrame(_ frame: NSRect) {
        let dict: [String: CGFloat] = [
            "x": frame.origin.x, "y": frame.origin.y,
            "w": frame.size.width, "h": frame.size.height
        ]
        UserDefaults.standard.set(dict, forKey: "BitMatch.windowFrame")
    }

    private func restoreWindowFrame() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "BitMatch.windowFrame"),
              let x = dict["x"] as? CGFloat, let y = dict["y"] as? CGFloat else { return }
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                var frame = window.frame
                // Only restore position, let size be computed from content
                frame.origin = NSPoint(x: x, y: y)
                // Validate the position is on a visible screen
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                    window.setFrameOrigin(frame.origin)
                }
            }
        }
    }
    
    // MARK: - View Modifier Methods
    @ViewBuilder
    private var windowObserversView: some View {
        styledMainContentView
            .onChange(of: idealWindowHeight) { _, newHeight in
                if !coordinator.isOperationInProgress {
                    updateWindowHeight(to: newHeight)
                }
            }
            .onChange(of: coordinator.currentMode) { _, _ in
                if !coordinator.isOperationInProgress {
                    updateWindowHeight(to: idealWindowHeight)
                }
            }
            .onChange(of: transferOptionsExpanded) { _, _ in
                if !coordinator.isOperationInProgress {
                    updateWindowHeight(to: idealWindowHeight)
                }
            }
            .onChange(of: verificationModeExpanded) { _, _ in
                if !coordinator.isOperationInProgress {
                    updateWindowHeight(to: idealWindowHeight)
                }
            }
            .onChange(of: coordinator.isOperationInProgress) { oldValue, newValue in
                handleOperationStateChange(oldValue: oldValue, newValue: newValue)
            }
    }
    
    @ViewBuilder
    private var notificationObserversView: some View {
        windowObserversView
    }
    
    @ViewBuilder
    private var keyboardShortcutsView: some View {
        notificationObserversView
            .onReceive(NotificationCenter.default.publisher(for: .switchToCopyMode)) { _ in
                guard !isModeSwitchLocked else { return }
                withAnimation { coordinator.switchMode(to: .copyAndVerify) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToCompareMode)) { _ in
                guard !isModeSwitchLocked else { return }
                withAnimation { coordinator.switchMode(to: .compareFolders) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToMasterReportMode)) { _ in
                guard !isModeSwitchLocked else { return }
                withAnimation { coordinator.switchMode(to: .masterReport) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .startVerification)) { _ in
                switch coordinator.currentMode {
                case .copyAndVerify:
                    // The shared Start: refuses what the Start button would.
                    Task { await coordinator.startCurrentMode() }
                case .compareFolders:
                    // ⌘R obeys the same readiness rule as the Compare button.
                    CompareFoldersView.startIfReady(coordinator)
                case .masterReport:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cancelOperation)) { _ in
                coordinator.cancelOperation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPreferences)) { _ in
                openPreferences()
            }
            .onReceive(NotificationCenter.default.publisher(for: .operationCancelledByUser)) { _ in
                showUserCancelToast()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dropRejected)) { notification in
                if let reason = notification.userInfo?["reason"] as? String {
                    showDropRejectionToast(reason)
                }
            }
            // Dev-only shortcuts
#if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .fillTestData)) { _ in
                DevModeManager.shared.fillTestDataOnly(coordinator: coordinator)
            }
            .onReceive(NotificationCenter.default.publisher(for: .addFakeQueueItem)) { _ in
                DevModeManager.shared.addFakeQueueItem(coordinator: coordinator)
            }
            // Legacy stress notification removed; use preset-specific hooks below
            .onReceive(NotificationCenter.default.publisher(for: .runStressTestSmall)) { _ in
                DevModeManager.shared.runStressTest(coordinator: coordinator, preset: .small)
            }
            .onReceive(NotificationCenter.default.publisher(for: .runStressTestMedium)) { _ in
                DevModeManager.shared.runStressTest(coordinator: coordinator, preset: .medium)
            }
            .onReceive(NotificationCenter.default.publisher(for: .runStressTestLarge)) { _ in
                DevModeManager.shared.runStressTest(coordinator: coordinator, preset: .large)
            }
#endif
            .onReceive(NotificationCenter.default.publisher(for: .clearTestData)) { _ in
                coordinator.resetForNewOperation()
            }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let startVerification = Notification.Name("startVerification")
    static let cancelOperation = Notification.Name("cancelOperation")
    static let switchToCopyMode = Notification.Name("switchToCopyMode")
    static let switchToCompareMode = Notification.Name("switchToCompareMode")
    static let switchToMasterReportMode = Notification.Name("switchToMasterReportMode")
    // NOTE: showPreferences, fakeTransferQueued, and simulateTransferCompletion are now in SharedModels.swift
    static let cameraLabelExpandedChanged = Notification.Name("cameraLabelExpandedChanged")
    static let verificationModeExpandedChanged = Notification.Name("verificationModeExpandedChanged")
    
    // Developer mode notifications
    static let fillTestData = Notification.Name("fillTestData")
    static let addFakeQueueItem = Notification.Name("addFakeQueueItem")
    static let clearTestData = Notification.Name("clearTestData")
    static let runStressTestSmall = Notification.Name("runStressTestSmall")
    static let runStressTestMedium = Notification.Name("runStressTestMedium")
    static let runStressTestLarge = Notification.Name("runStressTestLarge")
    static let dropRejected = Notification.Name("dropRejected")
    // operationCancelledByUser is defined in Shared/Core/Models/SharedModels.swift
}

// MARK: - Helpers
private extension MacMainView {
    func showUserCancelToast() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showCancelNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showCancelNotice = false
            }
        }
    }

    func showDropRejectionToast(_ reason: String) {
        dropRejectionMessage = reason
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showDropRejection = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showDropRejection = false
            }
        }
    }
}
