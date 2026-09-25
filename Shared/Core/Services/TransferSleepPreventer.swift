// TransferSleepPreventer.swift - Keeps the Mac awake while a copy or verify runs
import Foundation

/// Seam over `ProcessInfo` activities so tests can observe begin and end
/// without taking real power assertions.
protocol TransferSleepPreventing {
    /// Returns `nil` when this platform needs no activity.
    func beginActivity(reason: String) -> NSObjectProtocol?
    func endActivity(_ activity: NSObjectProtocol)
}

/// Holds an idle-sleep activity on macOS. iPad and iPhone keep awake through
/// `IOSBackgroundTaskService`, so this does nothing there.
struct ProcessInfoSleepPreventer: TransferSleepPreventing {
    func beginActivity(reason: String) -> NSObjectProtocol? {
        #if os(macOS)
        return ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )
        #else
        return nil
        #endif
    }

    func endActivity(_ activity: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
    }
}

/// One operation's hold on the activity. `release()` is safe to call more
/// than once; only the first call ends the activity.
@MainActor
final class TransferKeepAwake {
    private let preventer: TransferSleepPreventing
    private var activity: NSObjectProtocol?

    init(preventer: TransferSleepPreventing, reason: String) {
        self.preventer = preventer
        self.activity = preventer.beginActivity(reason: reason)
    }

    func release() {
        guard let activity else { return }
        self.activity = nil
        preventer.endActivity(activity)
    }
}
