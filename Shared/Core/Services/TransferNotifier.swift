// TransferNotifier.swift - Sends the "transfer finished" notification.
import Foundation
import UserNotifications
import BitMatchEngine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum TransferSummaryPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// Off until the person turns it on, and permission is asked only then
/// (`NotificationPermissionPolicy`). Notifies only when BitMatch is not the
/// app in front: the screen already shows the verdict.
@MainActor
final class TransferNotifier: ObservableObject {
    static let enabledKey = "BitMatchNotifyWhenTransferEnds"

    private let defaults: UserDefaults
    @Published private(set) var isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Asks for permission and turns notifications on if it is given.
    /// Returns whether they are on.
    @discardableResult
    func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        setEnabled(granted)
        return granted
    }

    func disable() { setEnabled(false) }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func post(_ notice: TransferFinishNotice) {
        guard isEnabled, !Self.appIsInFront else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                SharedLogger.warning("Could not post the finish notification: \(error.localizedDescription)", category: .transfer)
            }
        }
    }

    private static var appIsInFront: Bool {
        #if os(macOS)
        NSApp?.isActive ?? false
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }
}
