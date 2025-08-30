// Core/ViewModels/SettingsViewModel.swift
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var prefs = ReportPrefs()
    @Published var showOnlyIssues = false
    
    // MARK: - Initialization
    init() {
        // ReportPrefs handles its own persistence
        requestNotificationPermission()
    }
    
    // MARK: - Public Methods
    func toggleReportGeneration() {
        prefs.makeReport.toggle()
    }
    
    func updateVerificationMode(_ mode: VerificationMode) {
        prefs.verifyWithChecksum = mode.useChecksum
        // The OperationViewModel should observe this change
    }
    
    // MARK: - Notifications
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func scheduleNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
}
