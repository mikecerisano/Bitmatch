// BackgroundTaskManager.swift - iOS background processing scaffold
#if os(iOS)
import Foundation
import BackgroundTasks

enum BackgroundTaskManager {
    static let processingIdentifier = "com.bitmatch.app.transferprocessing"

    static func register() {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                handleProcessingTask(task: processingTask)
            }
        }
    }

    private static func handleProcessingTask(task: BGProcessingTask) {
        // NOTE: External volumes typically aren't available in background; this is a safe no-op placeholder.
        // Integration idea: if pending internal-storage operations remain, attempt resume work here.
        scheduleNext() // keep scheduling for future windows
        task.setTaskCompleted(success: true)
    }

    static func scheduleNext() {
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: processingIdentifier)
            request.requiresExternalPower = false
            request.requiresNetworkConnectivity = false
            do { try BGTaskScheduler.shared.submit(request) } catch { }
        }
    }
}
#endif

