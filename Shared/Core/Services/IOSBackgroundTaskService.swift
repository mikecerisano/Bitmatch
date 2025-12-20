// IOSBackgroundTaskService.swift - iOS background task and Live Activity management
import Foundation

#if os(iOS)
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Service that manages iOS background execution, screen dimming, and Live Activities
@MainActor
final class IOSBackgroundTaskService: ObservableObject {
    static let shared = IOSBackgroundTaskService()

    // MARK: - Published State
    @Published private(set) var backgroundTimeRemainingSeconds: Double?
    @Published private(set) var isInBackground: Bool = false

    // MARK: - Private State
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var previousBrightness: CGFloat?
    private var warnedLowBackgroundTime = false
    private var backgroundTimer: Timer?

    #if canImport(ActivityKit)
    private var liveActivityBox: Any?
    private var lastLiveActivityProgress: Double = -1
    private var lastLiveActivityFiles: Int = -1
    private var lastLiveActivityCurrentFile: String?
    private var lastLiveActivityUpdateTime: CFAbsoluteTime = 0
    #endif

    // MARK: - Configuration

    @inline(__always)
    private func isKeepAwakeEnabled() -> Bool {
        if let obj = UserDefaults.standard.object(forKey: "PreventAutoLockDuringTransfer") {
            return (obj as? Bool) ?? true
        }
        return true
    }

    @inline(__always)
    private func isDimScreenEnabled() -> Bool {
        if let obj = UserDefaults.standard.object(forKey: "DimScreenWhileAwake") {
            return (obj as? Bool) ?? true
        }
        return true
    }

    // MARK: - Public API

    /// Call when starting a long-running operation
    func beginOperation(estimatedFiles: Int) {
        if isKeepAwakeEnabled() {
            setIdleTimerDisabled(true)
            maybeDimScreen(true)
        }
        beginBackgroundTask()

        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            startLiveActivity(totalFiles: estimatedFiles)
        }
        #endif
    }

    /// Call when operation completes or is cancelled
    func endOperation() {
        endBackgroundTask()
        if isKeepAwakeEnabled() {
            maybeDimScreen(false)
            setIdleTimerDisabled(false)
        }

        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            endLiveActivity()
        }
        #endif

        scheduleNextBGProcessing()
    }

    /// Update Live Activity with current progress
    func updateProgress(_ progress: OperationProgress) {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            updateLiveActivity(from: progress)
        }
        #endif
    }

    // MARK: - Background Task Management

    private func beginBackgroundTask() {
        if backgroundTaskId == .invalid {
            backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "BitMatchFileTransfer") { [weak self] in
                self?.endBackgroundTask()
            }
        }
        warnedLowBackgroundTime = false
        startBackgroundTimeMonitor()
        backgroundTimeRemainingSeconds = UIApplication.shared.backgroundTimeRemaining
        isInBackground = UIApplication.shared.applicationState != .active
    }

    private func endBackgroundTask() {
        stopBackgroundTimeMonitor()
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    private func startBackgroundTimeMonitor() {
        stopBackgroundTimeMonitor()
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let remaining = UIApplication.shared.backgroundTimeRemaining
            Task { @MainActor in
                self.backgroundTimeRemainingSeconds = remaining
                self.isInBackground = UIApplication.shared.applicationState != .active
                if remaining.isFinite && remaining > 0 && remaining < 60 && !self.warnedLowBackgroundTime {
                    self.warnedLowBackgroundTime = true
                    self.notifyLowBackgroundTime()
                }
            }
        }
    }

    private func stopBackgroundTimeMonitor() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    private func notifyLowBackgroundTime() {
        Task { [weak self] in
            guard let self else { return }
            let allowed = await self.ensureNotificationPermission()
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = "Background time is running out"
            content.body = "Return to BitMatch to continue transfer."
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    private func ensureNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func scheduleNextBGProcessing() {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: "com.bitmatch.app.transferprocessing")
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = false
            _ = try? BGTaskScheduler.shared.submit(request)
        }
        #endif
    }

    // MARK: - Screen Management

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    private func maybeDimScreen(_ enable: Bool) {
        guard isDimScreenEnabled() else { return }
        if enable {
            if previousBrightness == nil {
                previousBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = max(0.05, min(0.2, UIScreen.main.brightness))
        } else if let prev = previousBrightness {
            UIScreen.main.brightness = prev
            previousBrightness = nil
        }
    }

    // MARK: - Live Activity Support

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    struct TransferActivityAttributes: ActivityAttributes {
        public struct ContentState: Codable, Hashable {
            var progress: Double
            var currentFile: String?
            var filesProcessed: Int
            var totalFiles: Int
            var etaSeconds: Double?
        }
        var title: String
    }

    @available(iOS 16.1, *)
    private func startLiveActivity(totalFiles: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TransferActivityAttributes(title: "Copy & Verify")
        let state = TransferActivityAttributes.ContentState(
            progress: 0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: totalFiles,
            etaSeconds: nil
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            liveActivityBox = activity
            lastLiveActivityProgress = 0
            lastLiveActivityFiles = 0
            lastLiveActivityCurrentFile = nil
            lastLiveActivityUpdateTime = CFAbsoluteTimeGetCurrent()
        } catch {
            SharedLogger.debug("Live Activity request failed: \(error)", category: .transfer)
        }
    }

    @available(iOS 16.1, *)
    private func updateLiveActivity(from progress: OperationProgress) {
        guard let act = liveActivityBox as? Activity<TransferActivityAttributes> else { return }

        // Throttle to ~1 Hz or meaningful change
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastLiveActivityUpdateTime
        let progressDelta = abs(progress.overallProgress - lastLiveActivityProgress)
        let filesChanged = progress.filesProcessed != lastLiveActivityFiles
        let fileNameChanged = progress.currentFile != lastLiveActivityCurrentFile

        guard elapsed >= 1.0 || progressDelta >= 0.01 || filesChanged || fileNameChanged else { return }

        let state = TransferActivityAttributes.ContentState(
            progress: progress.overallProgress,
            currentFile: progress.currentFile,
            filesProcessed: progress.filesProcessed,
            totalFiles: progress.totalFiles,
            etaSeconds: progress.timeRemaining
        )
        lastLiveActivityUpdateTime = now
        lastLiveActivityProgress = progress.overallProgress
        lastLiveActivityFiles = progress.filesProcessed
        lastLiveActivityCurrentFile = progress.currentFile
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await act.update(content) }
    }

    @available(iOS 16.1, *)
    private func endLiveActivity() {
        guard let act = liveActivityBox as? Activity<TransferActivityAttributes> else { return }
        Task { await act.end(nil, dismissalPolicy: .immediate) }
        liveActivityBox = nil
        lastLiveActivityProgress = -1
        lastLiveActivityFiles = -1
        lastLiveActivityCurrentFile = nil
        lastLiveActivityUpdateTime = 0
    }
    #endif
}

#else
// macOS stub - no-op implementation
@MainActor
final class IOSBackgroundTaskService: ObservableObject {
    static let shared = IOSBackgroundTaskService()

    @Published private(set) var backgroundTimeRemainingSeconds: Double?
    @Published private(set) var isInBackground: Bool = false

    func beginOperation(estimatedFiles: Int) {}
    func endOperation() {}
    func updateProgress(_ progress: OperationProgress) {}
}
#endif
