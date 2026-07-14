import Combine
import XCTest
@testable import BitMatch

@MainActor
final class AppCoordinatorBindingTests: XCTestCase {
    func testFileSelectionChangeNotifiesOnNextRunLoopTurn() {
        let coordinator = makeTestCoordinator()
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
        let coordinator = makeTestCoordinator()
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
        let coordinator = makeTestCoordinator()
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
        let coordinator = makeTestCoordinator()
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

    func testCoordinatorRejectsTwoCopyJobWithOneDestinationBeforeTransfer() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.fileSelectionViewModel.destinationURLs = [URL(fileURLWithPath: "/tmp/primary")]

        coordinator.startOperation()

        XCTAssertNil(coordinator.sharedCoordinator.sourceURL)
        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .notStarted)
    }

    func testCoordinatorRejectsChangedSourceBeforeTransfer() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.fileSelectionViewModel.sourceURL = URL(fileURLWithPath: "/tmp/other-card")

        coordinator.startOperation()

        XCTAssertNil(coordinator.sharedCoordinator.sourceURL)
        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .notStarted)
    }

    func testCoordinatorRejectsStartWhileGenericPreflightIsAnalyzing() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.fileSelectionViewModel.isFetchingSourceInfo = true

        coordinator.startOperation()

        XCTAssertNil(coordinator.sharedCoordinator.sourceURL)
        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .notStarted)
    }

    func testPhotographerCardFollowsAuthoritativeProgressStages() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.photographerJobViewModel.beginIngest(destinationCount: 2, sourceURL: coordinator.fileSelectionViewModel.sourceURL)

        coordinator.sharedCoordinator.progress = progress(stage: .verifying)
        drainMainRunLoop()

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .verifying)
    }

    func testTerminalStateWaitsForAuthoritativeResultArray() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        coordinator.photographerJobViewModel.beginIngest(destinationCount: 2, sourceURL: coordinator.fileSelectionViewModel.sourceURL)
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
        coordinator.photographerJobViewModel.beginIngest(destinationCount: 2, sourceURL: coordinator.fileSelectionViewModel.sourceURL)

        coordinator.cancelOperation()

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .cancelled)
    }

    func testDelayedVerifyingProgressCannotResurrectCompletedCard() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        primeSharedTransfer(coordinator)
        coordinator.sharedCoordinator.operationState = .inProgress
        coordinator.sharedCoordinator.progress = progress(stage: .copying)
        coordinator.sharedCoordinator.results = [
            verifiedRow(destination: "Primary"),
            verifiedRow(destination: "Secondary")
        ]
        coordinator.sharedCoordinator.operationState = .completed(
            OperationCompletionInfo(success: true, message: "Complete")
        )
        coordinator.sharedCoordinator.results = coordinator.sharedCoordinator.results
        coordinator.sharedCoordinator.progress = progress(stage: .verifying)

        waitForPresentationThrottle()

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .locallySafe)
    }

    func testDelayedCopyingProgressCannotResurrectCancelledCard() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        primeSharedTransfer(coordinator)
        coordinator.sharedCoordinator.operationState = .inProgress
        coordinator.sharedCoordinator.progress = progress(stage: .verifying)
        coordinator.sharedCoordinator.operationState = .cancelled
        coordinator.sharedCoordinator.progress = progress(stage: .copying)

        waitForPresentationThrottle()

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .cancelled)
    }

    func testAcceptedOperationStateBeginsIngestAndFailedOperationEndsInIssues() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()
        primeSharedTransfer(coordinator)

        coordinator.sharedCoordinator.operationState = .inProgress
        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .copying)

        coordinator.sharedCoordinator.operationState = .failed
        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .issues)
    }

    func testRejectedStartEndsPreparedCardInIssuesWithoutMarkingCopying() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()

        coordinator.sharedCoordinator.operationState = .failed

        XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .issues)
    }

    func testCompareFolderEventsNeverMutatePreparedPhotographerCard() throws {
        let terminalStates: [OperationState] = [
            .completed(OperationCompletionInfo(success: true, message: "Compared")),
            .failed,
            .cancelled
        ]

        for terminalState in terminalStates {
            let (coordinator, store) = try makePreparedPhotographerCoordinator()
            coordinator.switchMode(to: .compareFolders)
            XCTAssertEqual(store.saveCount, 2)

            coordinator.sharedCoordinator.operationState = .inProgress
            coordinator.sharedCoordinator.progress = progress(stage: .copying)
            coordinator.sharedCoordinator.progress = progress(stage: .verifying)
            coordinator.sharedCoordinator.operationState = terminalState
            coordinator.sharedCoordinator.results = [verifiedRow(destination: "Comparison")]

            XCTAssertEqual(coordinator.photographerJobViewModel.activeCard?.localState, .notStarted)
            XCTAssertEqual(store.saveCount, 2)
        }
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
        let sourceURL = URL(fileURLWithPath: "/tmp/card")
        let signature = PhotographerSetupSignature(
            clientName: "Smith",
            jobName: "Smith Wedding",
            eventDate: Date(timeIntervalSince1970: 100),
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            cardNumber: 1,
            recipe: .wedding
        )
        try viewModel.prepareCard(
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            sourceURL: sourceURL,
            setupSignature: signature,
            analysis: CardAnalysis(
                fingerprint: "preliminary",
                fileCount: 1,
                totalBytes: 100,
                companionGroups: [],
                sourcePaths: ["/card/A.ARW"]
            )
        )
        let coordinator = AppCoordinator(photographerJobViewModel: viewModel)
        coordinator.fileSelectionViewModel.sourceURL = sourceURL
        coordinator.fileSelectionViewModel.isFetchingSourceInfo = false
        coordinator.fileSelectionViewModel.destinationURLs = [
            URL(fileURLWithPath: "/tmp/primary"),
            URL(fileURLWithPath: "/tmp/secondary")
        ]
        return (coordinator, store)
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

    private func primeSharedTransfer(_ coordinator: AppCoordinator) {
        coordinator.sharedCoordinator.sourceURL = coordinator.fileSelectionViewModel.sourceURL
        coordinator.sharedCoordinator.destinationURLs = coordinator.fileSelectionViewModel.destinationURLs
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

    private func makeTestCoordinator() -> AppCoordinator {
        AppCoordinator(photographerJobViewModel: PhotographerJobViewModel(store: InMemoryPhotographerJobStore()))
    }

    private func waitForPresentationThrottle() {
        let delayed = expectation(description: "presentation throttle drains")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { delayed.fulfill() }
        wait(for: [delayed], timeout: 1)
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
