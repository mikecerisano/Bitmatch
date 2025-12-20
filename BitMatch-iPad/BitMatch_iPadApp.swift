// BitMatch_iPadApp.swift - iPad app entry point
import SwiftUI
import UserNotifications
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@main
struct BitMatch_iPadApp: App {
    private let notifDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notifDelegate
        // Register background task handler (Info.plist contains permitted identifier)
        registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    setupiOS()
                }
        }
    }
    
    private func setupiOS() {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                SharedLogger.error("Notification permission error: \(error)")
            }
        }
    }

    private func registerBackgroundTasks() {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.bitmatch.app.transferprocessing", using: nil) { task in
                guard let processing = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                // Minimal handler: schedule next and complete.
                let request = BGProcessingTaskRequest(identifier: "com.bitmatch.app.transferprocessing")
                request.requiresExternalPower = false
                request.requiresNetworkConnectivity = false
                _ = try? BGTaskScheduler.shared.submit(request)
                processing.setTaskCompleted(success: true)
            }
        }
        #endif
    }
}

// Shared notification delegate
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
