// Core/ViewModels/SettingsViewModel.swift
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var prefs = ReportPrefs() {
        didSet {
            // Persist full report prefs and specific makeReport flag
            persistPrefs()
        }
    }
    @Published var showOnlyIssues = false
    
    // MARK: - Initialization
    init() {
        // ReportPrefs handles its own persistence.
        // Notification permission is never requested here: it is a
        // user-visible prompt and fires lazily when a notification is
        // actually scheduled, or via requestNotificationPermission().
        // Load persisted preferences if available
        loadPrefs()
    }
    
    // MARK: - Public Methods
    func toggleReportGeneration() {
        prefs.makeReport.toggle()
    }
    
    func updateVerificationMode(_ mode: VerificationMode) {
        prefs.verifyWithChecksum = mode.useChecksum
    }
    
    // MARK: - Notifications
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                SharedLogger.error("Notification permission error: \(error)", category: .transfer)
            }
        }
    }
    
    func scheduleNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.addNotification(title: title, body: body)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                ) { granted, error in
                    if let error = error {
                        SharedLogger.error("Notification permission error: \(error)", category: .transfer)
                    }
                    if granted {
                        self.addNotification(title: title, body: body)
                    }
                }
            default:
                SharedLogger.warning("Notifications not authorized; skipping scheduled notification", category: .transfer)
            }
        }
    }

    private func addNotification(title: String, body: String) {
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
                SharedLogger.error("Failed to schedule notification: \(error)", category: .transfer)
            }
        }
    }
}

private extension SettingsViewModel {
    static let makeReportDefaultsKey = "BitMatch_MakeReportEnabled"
    static let reportPrefsKey = "BitMatch_ReportPrefs_JSON"

    func persistPrefs() {
        // Persist makeReport separately for fast access by other modules
        UserDefaults.standard.set(prefs.makeReport, forKey: Self.makeReportDefaultsKey)
        // Persist entire prefs as JSON-encoded data
        do {
            let data = try JSONEncoder().encode(prefs)
            UserDefaults.standard.set(data, forKey: Self.reportPrefsKey)
        } catch {
            SharedLogger.error("Failed to persist ReportPrefs: \(error)", category: .transfer)
        }
    }

    func loadPrefs() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.reportPrefsKey) {
            do {
                let decoded = try JSONDecoder().decode(ReportPrefs.self, from: data)
                prefs = decoded
            } catch {
                SharedLogger.warning("Failed to load ReportPrefs, falling back to defaults: \(error)", category: .transfer)
                if defaults.object(forKey: Self.makeReportDefaultsKey) != nil {
                    prefs.makeReport = defaults.bool(forKey: Self.makeReportDefaultsKey)
                }
            }
        } else if defaults.object(forKey: Self.makeReportDefaultsKey) != nil {
            // Fallback path for older versions that only stored makeReport
            prefs.makeReport = defaults.bool(forKey: Self.makeReportDefaultsKey)
        }
    }
}
