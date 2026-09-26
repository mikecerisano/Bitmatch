// BitMatchApp.swift - Main app with dark theme configuration
import SwiftUI
import UserNotifications

// Visual effect for window background
struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// Custom window styling
struct CustomWindowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(VisualEffect(material: .hudWindow, blendingMode: .behindWindow))
    }
}

extension View {
    func customWindowStyle() -> some View {
        self.modifier(CustomWindowStyle())
    }
}

// Delegate to handle foreground notifications
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}

@main
struct BitMatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var environment: MacAppEnvironment
    #if DEBUG
    @ObservedObject private var devModeManager = DevModeManager.shared
    #endif
    private let notifDelegate = NotificationDelegate()
    // InterfaceLab is a development tool: the launch path is DEBUG-only so a
    // stray --interface-lab argument can never swap the Release UI.
    private let launchesInterfaceLab: Bool = {
#if DEBUG
        InterfaceLabLaunchConfiguration.isRequested(
            arguments: ProcessInfo.processInfo.arguments
        )
#else
        false
#endif
    }()

    init() {
        _environment = StateObject(wrappedValue: MacAppEnvironment.make())
        UNUserNotificationCenter.current().delegate = notifDelegate
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if launchesInterfaceLab { InterfaceLabView() }
                else { ContentView(environment: environment).preferredColorScheme(.dark) }
#else
                ContentView(environment: environment).preferredColorScheme(.dark)
#endif
            }
            .onAppear { setupWindow() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            OperationCommands()
            
            // Into the system View menu: a CommandMenu("View") adds a second one.
            CommandGroup(before: .toolbar) {
                Button("Copy & Verify Mode") {
                    NotificationCenter.default.post(name: .switchToCopyMode, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Compare Folders Mode") {
                    NotificationCenter.default.post(name: .switchToCompareMode, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Master Report") {
                    NotificationCenter.default.post(name: .switchToMasterReportMode, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)
                Divider()
            }
            
            #if DEBUG
            CommandMenu("Developer") {
                Button("Open Interface Lab") {
                    InterfaceLabLauncher.open()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                Button(devModeManager.isDevModeEnabled ? "Disable Dev Mode" : "Enable Dev Mode") {
                    devModeManager.isDevModeEnabled.toggle()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                
                Divider()
                
                Button("Fill Test Data") {
                    NotificationCenter.default.post(name: .fillTestData, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!devModeManager.isDevModeEnabled)
                

                Divider()
                // Real files in temp folders, no fake data: available
                // whenever this menu is, with dev mode on or off.
                Button("Stress Test (Small)") { devModeManager.runStressTest(preset: .small) }
                    .disabled(devModeManager.isStressTestRunning)
                Button("Stress Test (Medium)") { devModeManager.runStressTest(preset: .medium) }
                    .disabled(devModeManager.isStressTestRunning)
                Button("Stress Test (Large)") { devModeManager.runStressTest(preset: .large) }
                    .disabled(devModeManager.isStressTestRunning)

                Divider()
                Toggle("Verbose Dev Logs", isOn: $devModeManager.verboseLogs)
                    .disabled(!devModeManager.isDevModeEnabled)
                
                Divider()
                
                Button("Clear All Data") {
                    NotificationCenter.default.post(name: .clearTestData, object: nil)
                }
                .disabled(!devModeManager.isDevModeEnabled)
            }
            #endif
        }

        Settings {
            PreferencesWindow(
                coordinator: environment.coordinator,
                cameraAutoSource: environment.cameraAutoSource,
                remoteBackups: environment.remoteBackups
            )
            .macCompanions(environment)
        }
    }
    
    private func setupWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                // Configure window appearance
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                if WindowPresentationPolicy.allowsManualResizing {
                    window.styleMask.insert(.resizable)
                }
                window.isMovableByWindowBackground = true
                window.backgroundColor = NSColor.black
                
                // Start compact, then let the workbench grow into a proper review surface.
                window.setContentSize(NSSize(width: WindowPresentationPolicy.initialWidth, height: WindowPresentationPolicy.initialHeight))
                window.minSize = NSSize(width: WindowPresentationPolicy.minimumWidth, height: WindowPresentationPolicy.minimumHeight)
                window.maxSize = NSSize(width: WindowPresentationPolicy.maximumWidth, height: WindowPresentationPolicy.maximumHeight)
                
                // Make window fully opaque
                window.isOpaque = true
                window.alphaValue = 1.0
                window.hasShadow = true
                
                // Set window level
                window.level = .normal
                
                let savedFrame = UserDefaults.standard.dictionary(forKey: "BitMatch.windowFrame")
                let hasSavedPlacement = savedFrame?["x"] as? CGFloat != nil
                    && savedFrame?["y"] as? CGFloat != nil
                if WindowPresentationPolicy.shouldCenterWindow(
                    hasSavedPlacement: hasSavedPlacement,
                    isInterfaceLab: launchesInterfaceLab
                ) {
                    window.center()
                }
            }
        }
    }
}

/// File menu transfer commands. New Transfer and Eject publish through the
/// focused main window; Eject exists only for a safe, removable card.
struct OperationCommands: Commands {
    @FocusedValue(\.canCancelOperation) private var canCancelOperation
    @FocusedValue(\.canStartNewTransfer) private var canStartNewTransfer
    @FocusedValue(\.ejectCardTitle) private var ejectCardTitle

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(TransferMenuPresentation.newTransferTitle) {
                NotificationCenter.default.post(name: .newTransfer, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(canStartNewTransfer != true)
        }

        // Into the system File menu, so it keeps its place; a
        // CommandMenu("File") adds a second File menu after View.
        CommandGroup(after: .newItem) {
            Button("Start Verification") {
                NotificationCenter.default.post(name: .startVerification, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button(ejectCardTitle ?? TransferMenuPresentation.unavailableEjectTitle) {
                NotificationCenter.default.post(name: .ejectCard, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(ejectCardTitle == nil)

            Divider()

            Button("Cancel Operation…") {
                NotificationCenter.default.post(name: .cancelOperation, object: nil)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(canCancelOperation != true)
        }
    }
}

/// Published by the main window so the File menu knows whether anything runs.
struct CanCancelOperationKey: FocusedValueKey {
    typealias Value = Bool
}

struct CanStartNewTransferKey: FocusedValueKey {
    typealias Value = Bool
}

struct EjectCardTitleKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    var canCancelOperation: Bool? {
        get { self[CanCancelOperationKey.self] }
        set { self[CanCancelOperationKey.self] = newValue }
    }

    var canStartNewTransfer: Bool? {
        get { self[CanStartNewTransferKey.self] }
        set { self[CanStartNewTransferKey.self] = newValue }
    }

    var ejectCardTitle: String? {
        get { self[EjectCardTitleKey.self] }
        set { self[EjectCardTitleKey.self] = newValue }
    }
}

// App Delegate for early setup
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Disable window restoration to avoid className=(null) warnings
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
}

// NOTE: Notification.Name extensions are defined in ContentView.swift
// - startVerification
// - cancelOperation
// - switchToCopyMode
// - switchToCompareMode
// - switchToMasterReportMode
