// BitMatch_iPadApp.swift - iPad app entry point
import SwiftUI
import UserNotifications

@main
struct BitMatch_iPadApp: App {
    private let notifDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notifDelegate
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
                print("Notification permission error: \(error)")
            }
        }
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
