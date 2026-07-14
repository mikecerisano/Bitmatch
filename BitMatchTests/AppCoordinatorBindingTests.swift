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

        XCTAssertEqual(coordinator.operationState, .notStarted)
        coordinator.sharedCoordinator.operationState = .idle
        XCTAssertEqual(coordinator.operationState, .idle)
        notificationReceived.enable()

        assertNotificationReceivedOnNextRunLoopTurn(notificationReceived)
    }

    func testFilesPerSecondChangeNotifiesOnNextRunLoopTurn() {
        let coordinator = AppCoordinator()
        drainMainRunLoop()
        let notificationReceived = NotificationState()
        let notification = coordinator.objectWillChange.sink { _ in
            notificationReceived.recordIfEnabled()
        }
        defer { notification.cancel() }

        XCTAssertNil(coordinator.formattedSpeed)
        notificationReceived.enable()
        coordinator.progressViewModel.filesPerSecond = 24
        XCTAssertEqual(coordinator.formattedSpeed, "24 files/s")

        assertNotificationReceivedOnNextRunLoopTurn(notificationReceived)
    }

    func testVerificationModeChangeNotifiesOnNextRunLoopTurn() {
        let coordinator = AppCoordinator()
        drainMainRunLoop()
        let notificationReceived = NotificationState()
        let notification = coordinator.objectWillChange.sink { _ in
            notificationReceived.recordIfEnabled()
        }
        defer { notification.cancel() }

        let originalMode = coordinator.verificationMode
        let updatedMode: VerificationMode = originalMode == .quick ? .standard : .quick
        notificationReceived.enable()
        coordinator.sharedCoordinator.verificationMode = updatedMode
        XCTAssertEqual(coordinator.verificationMode, updatedMode)

        assertNotificationReceivedOnNextRunLoopTurn(notificationReceived)
        coordinator.sharedCoordinator.verificationMode = originalMode
    }

    func testPreparedPhotographerRecipeIsAppliedBeforeSharedSettingsSynchronization() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        var base = CameraLabelSettings()
        base.label = "Legacy"
        coordinator.cameraLabelViewModel.destinationLabelSettings = base

        coordinator.startOperation()

        XCTAssertEqual(
            coordinator.sharedCoordinator.cameraLabelSettings.destinationPathComponents,
            coordinator.photographerJobViewModel.renderedRecipe?.components
        )
        XCTAssertEqual(coordinator.sharedCoordinator.cameraLabelSettings.label, "Legacy")
    }

    func testPhotographerCardFollowsAuthoritativeProgressStages() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.photographerJobViewModel.beginIngest(destinationCount: 2)

        coordinator.sharedCoordinator.progress = progress(stage: .verifying)
        drainMainRunLoop()

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .verifying)
    }

    func testTerminalStateWaitsForAuthoritativeResultArray() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.photographerJobViewModel.beginIngest(destinationCount: 2)
        coordinator.sharedCoordinator.progress = progress(stage: .verifying)
        drainMainRunLoop()
        coordinator.sharedCoordinator.results = [verifiedRow(destination: "Primary")]

        coordinator.sharedCoordinator.operationState = .completed(
            OperationCompletionInfo(success: true, message: "Complete")
        )
        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .verifying)

        coordinator.sharedCoordinator.results = [
            verifiedRow(destination: "Primary"),
            verifiedRow(destination: "Secondary")
        ]

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .locallySafe)
    }

    func testCancellationCancelsPreparedPhotographerCard() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.photographerJobViewModel.beginIngest(destinationCount: 2)

        coordinator.cancelOperation()

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .cancelled)
    }

    private func makePreparedPhotographerCoordinator() throws -> (AppCoordinator, InMemoryPhotographerJobStore) {
        let store = InMemoryPhotographerJobStore()
        let viewModel = PhotographerJobViewModel(
            store: store,
            now: { Date(timeIntervalSince1970: 200) }
        )
        viewModel.createWeddingJob(
            clientName: "Smith",
            jobName: "Smith Wedding",
            eventDate: Date(timeIntervalSince1970: 100)
        )
        try viewModel.prepareCard(
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            analysis: CardAnalysis(
                fingerprint: "preliminary",
                fileCount: 1,
                totalBytes: 100,
                companionGroups: []
            )
        )
        return (AppCoordinator(photographerJobViewModel: viewModel), store)
    }

    private func progress(stage: ProgressStage) -> OperationProgress {
        OperationProgress(
            overallProgress: 0.5,
            currentFile: "A.ARW",
            filesProcessed: 0,
            totalFiles: 1,
            currentStage: stage,
            speed: nil,
            timeRemaining: nil
        )
    }

    private func verifiedRow(destination: String) -> ResultRow {
        ResultRow(
            path: "/card/A.ARW",
            status: "✅ Verified",
            size: 100,
            checksum: "abc",
            destination: destination,
            destinationPath: "/\(destination.lowercased())/A.ARW"
        )
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
