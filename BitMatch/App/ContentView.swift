// App/ContentView.swift - Updated to use new architecture
import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()
    @ObservedObject private var errorHandler = GlobalErrorHandler.shared
#if DEBUG
    @ObservedObject private var devModeManager = DevModeManager.shared
#endif
    @State private var showResumeDialog = false
    @State private var resumableOperation: OperationStateManager.PersistedOperation?
    
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
            // Dynamic height based on number of destinations
            let baseSourceDestinationHeight: CGFloat = 180
            let additionalDestinationHeight: CGFloat = 50 // Height per additional destination
            let destinationCount = coordinator.fileSelectionViewModel.destinationURLs.count
            let extraHeight = destinationCount > 1 ? CGFloat(destinationCount - 1) * additionalDestinationHeight : 0
            
            let sourceDestinationHeight = baseSourceDestinationHeight + extraHeight
            let controlPanelBaseHeight: CGFloat = 120  // Base control panel
            
            totalHeight += sourceDestinationHeight + controlPanelBaseHeight
            
            if transferOptionsExpanded { totalHeight += 330 }
            
        case .compareFolders:
            let foldersHeight: CGFloat = 180  // Both folder panels (matches the fixed height in CompareFoldersView)
            let actionsHeight: CGFloat = 120  // Actions & Options section (same as Copy to Backups base)
            totalHeight += foldersHeight + actionsHeight
            
            // Add height for expanded sections (like Copy to Backups does)
            if verificationModeExpanded {
                totalHeight += 150  // Verification mode expanded section
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
            .onAppear {
                restoreWindowFrame()
                updateWindowSize(width: compactWindowWidth, height: idealWindowHeight)
                checkForResumableOperations()
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
            .alert("Confirm SFTP Host Key", isPresented: Binding(get: { coordinator.hostTrustPrompt != nil }, set: { if !$0 { coordinator.confirmHostTrust(false) } })) {
                Button("Trust Host Key") { coordinator.confirmHostTrust(true) }
                Button("Cancel", role: .cancel) { coordinator.confirmHostTrust(false) }
            } message: {
                if let prompt = coordinator.hostTrustPrompt {
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
                    ToastView(icon: "xmark.circle", message: "User cancelled transfer", tint: .red)
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
            mainScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(darkBackground)
    }
    
    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                resumeBannerArea
                mainContentSwitch
                resultsArea
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxHeight: lockHeight ? contentHeight : 900)
    }
    
    @ViewBuilder
    private var resumeBannerArea: some View {
        if showResumeDialog, let operation = resumableOperation {
            resumeBanner(for: operation)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
        }
    }
    
    @ViewBuilder
    private var mainContentSwitch: some View {
        switch coordinator.completionState {
        case .idle, .inProgress:
            // While in progress, keep showing the active mode's view.
            // Copy & Verify view renders its compact progress UI when in progress.
            modeSpecificView
        default:
            completionView
                .frame(height: lockHeight ? contentHeight : nil)
        }
    }
    
    @ViewBuilder
    private var resultsArea: some View {
        if coordinator.currentMode != .masterReport &&
           (coordinator.isOperationInProgress ||
            (!coordinator.results.isEmpty && coordinator.completionState != .idle)) {
            ResultsTableView(
                coordinator: coordinator,
                showOnlyIssues: Binding(
                    get: { coordinator.settingsViewModel.showOnlyIssues },
                    set: { coordinator.settingsViewModel.showOnlyIssues = $0 }
                )
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - View Components
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("BitMatch")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            // Centered mode selector
            if !coordinator.isOperationInProgress {
                ModeSelectorView(mode: $coordinator.currentMode)
                    .transition(.opacity)
            }
            
            Spacer()
            
            // Preferences gear button
            Button {
                openPreferences()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Preferences")
        }
        .padding(.horizontal, 20)  // Reduced from 24 to 20 - using half the space savings
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
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
                    showReportSettings: .constant(false),
                    verificationModeExpanded: $verificationModeExpanded
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
    
    @ViewBuilder
    private var completionView: some View {
        CompletionView(
            message: completionMessage,
            iconName: completionIcon,
            iconColor: completionColor,
            onNewTask: {
                coordinator.resetForNewOperation()
                // FIX: Also reset height lock when starting new task
                lockHeight = false
                isOperationActive = false
            }
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 1.05).combined(with: .opacity)
        ))
    }
    
    @ViewBuilder
    private func resumeBanner(for operation: OperationStateManager.PersistedOperation) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Resume Previous Operation?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("\(operation.processedCount) of \(operation.totalCount) files completed")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                
                // Show time since interruption
                if let lastCheckpoint = operation.checkpoints.last {
                    let timeSince = Date().timeIntervalSince(lastCheckpoint.timestamp)
                    Text("Last active \(formatTimeInterval(timeSince)) ago")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Start Fresh") {
                    withAnimation {
                        showResumeDialog = false
                        OperationStateManager.clearState(for: operation.id)
                    }
                }
                .buttonStyle(CustomButtonStyle(isDestructive: true))
                
                Button {
                    withAnimation {
                        showResumeDialog = false
                        // Phase 3: resume via SharedAppCoordinator
                        Task { await coordinator.sharedCoordinator.resumeOperation() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Resume Now")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.yellow)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
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
            preferencesWindowController = PreferencesWindowController(coordinator: coordinator)
        }
        
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Helpers
    
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
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "moments"
        } else if interval < 3600 {
            return "\(Int(interval / 60)) minutes"
        } else if interval < 86400 {
            return "\(Int(interval / 3600)) hours"
        } else {
            return "\(Int(interval / 86400)) days"
        }
    }
    
    private func checkForResumableOperations() {
        if let resumeInfo = OperationStateManager.getResumeInfo() {
            if resumeInfo.shouldResume {
                resumableOperation = resumeInfo.operation
                withAnimation(.spring(response: 0.4)) {
                    showResumeDialog = true
                }
            }
        }
    }
    
    // MARK: - Completion State Helpers
    private var completionMessage: String {
        switch coordinator.completionState {
        case .success(let msg): return msg
        case .issues(let msg): return msg
        case .failed(let msg): return msg
        case .idle: return ""
        case .inProgress: return ""
        }
    }
    
    private var completionIcon: String {
        switch coordinator.completionState {
        case .success: return "checkmark.circle.fill"
        case .issues: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .idle: return ""
        case .inProgress: return "clock.fill"
        }
    }
    
    private var completionColor: Color {
        switch coordinator.completionState {
        case .success: return .green
        case .issues: return .yellow
        case .failed: return .red
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
                withAnimation { coordinator.switchMode(to: .copyAndVerify) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToCompareMode)) { _ in
                withAnimation { coordinator.switchMode(to: .compareFolders) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToMasterReportMode)) { _ in
                withAnimation { coordinator.switchMode(to: .masterReport) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .startVerification)) { _ in
                if coordinator.currentMode != .masterReport {
                    coordinator.startOperation()
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
private extension ContentView {
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
