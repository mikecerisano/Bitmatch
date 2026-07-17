import Foundation

/// Permission is contextual: BitMatch asks only when a person explicitly
/// enables transfer notifications, never while they are trying to begin work.
enum NotificationPermissionPolicy {
    static let requestsAtLaunch = false
}
