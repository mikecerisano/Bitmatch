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
        completionHandler([.banner, .sound])
    }
}

@main
struct BitMatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #if DEBUG
    @ObservedObject private var devModeManager = DevModeManager.shared
    #endif
    private let notifDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notifDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    setupWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            // Add Preferences to the main app menu
            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: .showPreferences, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("File") {
                Button("Start Verification") {
                    NotificationCenter.default.post(name: .startVerification, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Cancel Operation") {
                    NotificationCenter.default.post(name: .cancelOperation, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
            }
            
            CommandMenu("View") {
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
            }
            
            #if DEBUG
            CommandMenu("Developer") {
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
                
                Button("Add Fake Queue Item") {
                    NotificationCenter.default.post(name: .addFakeQueueItem, object: nil)
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
                .disabled(!devModeManager.isDevModeEnabled)

                Divider()
                Button("Stress Test (Small)") { NotificationCenter.default.post(name: .runStressTestSmall, object: nil) }
                    .disabled(!devModeManager.isDevModeEnabled)
                Button("Stress Test (Medium)") { NotificationCenter.default.post(name: .runStressTestMedium, object: nil) }
                    .disabled(!devModeManager.isDevModeEnabled)
                Button("Stress Test (Large)") { NotificationCenter.default.post(name: .runStressTestLarge, object: nil) }
                    .disabled(!devModeManager.isDevModeEnabled)

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
    }
    
    private func setupWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                // Configure window appearance
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.styleMask.remove(.resizable) // Disable user resizing
                window.isMovableByWindowBackground = true
                window.backgroundColor = NSColor.black
                
                // UPDATED: Extreme compactness with tiny center gap when empty
                window.setContentSize(NSSize(width: 680, height: 650))   // Extreme width reduction
                window.minSize = NSSize(width: 580, height: 550)         // Minimum width for compressed state
                window.maxSize = NSSize(width: 1080, height: 1000)       // Allow wider expansion
                
                // Make window fully opaque
                window.isOpaque = true
                window.alphaValue = 1.0
                window.hasShadow = true
                
                // Set window level
                window.level = .normal
                
                // Center window on screen
                window.center()
            }
        }
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
// - cameraLabelExpandedChanged
// - verificationModeExpandedChanged
