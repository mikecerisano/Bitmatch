import Combine
import XCTest
@testable import BitMatch

@MainActor
final class AppCoordinatorBindingTests: XCTestCase {
    func testFileSelectionChangeNotifiesOnNextRunLoopTurn() {
        let coordinator = AppCoordinator()
        drainMainRunLoop()
        let notificationReceived = NotificationState()
        let notification = coordinator.objectWillChange.sink { _ in
            notificationReceived.recordIfEnabled()
        }
        defer { notification.cancel() }

        coordinator.fileSelectionViewModel.sourceURL = URL(fileURLWithPath: "/tmp/source")
        notificationReceived.enable()

        assertNotificationReceivedOnNextRunLoopTurn(notificationReceived)
    }

    func testSharedCoordinatorStateChangeNotifiesOnNextRunLoopTurn() {
        let coordinator = AppCoordinator()
        drainMainRunLoop()
        let notificationReceived = NotificationState()
        let notification = coordinator.objectWillChange.sink { _ in
            notificationReceived.recordIfEnabled()
        }
        defer { notification.cancel() }

        notificationReceived.enable()
        coordinator.sharedCoordinator.resetForNewOperation()

        assertNotificationReceivedOnNextRunLoopTurn(notificationReceived)
    }

    private func drainMainRunLoop() {
        let nextTurn = expectation(description: "main run loop drains")
        RunLoop.main.perform {
            nextTurn.fulfill()
        }
        wait(for: [nextTurn], timeout: 1)
    }

    private func assertNotificationReceivedOnNextRunLoopTurn(_ notificationReceived: NotificationState) {
        let nextTurn = expectation(description: "coordinator notifies on the next run loop turn")
        RunLoop.main.perform {
            let received = notificationReceived.received
            XCTAssertTrue(received)
            nextTurn.fulfill()
        }
        wait(for: [nextTurn], timeout: 1)
    }
}

private final class NotificationState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var isEnabled = false

    var received: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func enable() {
        lock.lock()
        isEnabled = true
        lock.unlock()
    }

    func recordIfEnabled() {
        lock.lock()
        guard isEnabled else {
            lock.unlock()
            return
        }
        value = true
        lock.unlock()
    }
}
