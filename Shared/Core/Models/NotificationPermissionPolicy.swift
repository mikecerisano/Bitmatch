import Foundation
import UserNotifications

/// Permission is contextual: BitMatch asks only when a person explicitly
/// enables transfer notifications, never while they are trying to begin work.
enum NotificationPermissionPolicy {
    static let requestsAtLaunch = false

    static func canPostWithoutRequest(status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}
