import Combine
import XCTest
@testable import BitMatch

@MainActor
final class AppCoordinatorBindingTests: XCTestCase {
    private let renderedPackage = "1970-01-01_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001"

    func testChangingMacComparisonFoldersClearsPreviousEvidence() {
        let coordinator = makeTestCoordinator()
        coordinator.leftURL = URL(fileURLWithPath: "/tmp/old-source")
        coordinator.rightURL = URL(fileURLWithPath: "/tmp/old-backup")
        coordinator.sharedCoordinator.lastCompareStats = CompareStats(
            onlyInLeftCount: 0, onlyInRightCount: 1, commonCount: 1, mismatchedCount: 0,
            onlyInRightPaths: ["extra.mov"])

        coordinator.leftURL = URL(fileURLWithPath: "/tmp/new-source")
        XCTAssertNil(coordinator.sharedCoordinator.lastCompareStats)
        XCTAssertEqual(coordinator.sharedCoordinator.leftURL, coordinator.leftURL)

        coordinator.sharedCoordinator.lastCompareStats = CompareStats(
            onlyInLeftCount: 0, onlyInRightCount: 0, commonCount: 1, mismatchedCount: 0)
        coordinator.rightURL = URL(fileURLWithPath: "/tmp/new-backup")
        XCTAssertNil(coordinator.sharedCoordinator.lastCompareStats)
        XCTAssertEqual(coordinator.sharedCoordinator.rightURL, coordinator.rightURL)
    }

    func testFileSelectionChangeNotifiesOnNextRunLoopTurn() {
        let coordinator = makeTestCoordinator()
        drainMainRunLoop()
        let notificationReceived = NotificationState()
        let notification = coordinator.objectWillChange.sink { _ in
            notificationReceived.recordIfEnabled()
        }
        defer { notification.cancel() }

        coordinator.sourceURL = URL(fileURLWithPath: "/tmp/source")
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

    func testNormalCopyDoesNotRequirePhotographerCardPreparation() {
        let coordinator = makeTestCoordinator()

        XCTAssertFalse(coordinator.photographerJobViewModel.hasPreparedIngestAwaitingStart)
    }

    /// Plant: in `AppCoordinator.init`, pass no `photographerJobViewModel`
    /// to `SharedAppCoordinator` (it then builds its own).
    func testMacHasOneJobViewModel() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()

        XCTAssertTrue(coordinator.photographerJobViewModel === coordinator.sharedCoordinator.photographerJobViewModel)
        XCTAssertTrue(coordinator.sharedCoordinator.photographerJobViewModel.hasPreparedIngestAwaitingStart)
    }

    func testPreparedPhotographerCardRequiresPhotographerStartEligibility() throws {
        let (coordinator, _) = try makePreparedPhotographerCoordinator()

        XCTAssertTrue(coordinator.photographerJobViewModel.hasPreparedIngestAwaitingStart)
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
        let coordinator = AppCoordinator(photographerJobViewModel: viewModel, platformManager: SilentPlatformManager())
        coordinator.sourceURL = sourceURL
        coordinator.destinationURLs = [
            URL(fileURLWithPath: "/tmp/primary"),
            URL(fileURLWithPath: "/tmp/secondary")
        ]
        waitUntilSourceScanned(coordinator)
        return (coordinator, store)
    }

    /// The start guard waits for the source scan; let it finish.
    private func waitUntilSourceScanned(_ coordinator: AppCoordinator) {
        let deadline = Date().addingTimeInterval(5)
        while coordinator.isAnalysingSource && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(coordinator.isAnalysingSource, "source scan did not finish")
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
            destinationPath: "/\(destination.lowercased())/\(renderedPackage)/A.ARW"
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
        AppCoordinator(
            photographerJobViewModel: PhotographerJobViewModel(store: InMemoryPhotographerJobStore()),
            platformManager: SilentPlatformManager()
        )
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

private enum CoordinatorFixtureError: Error {
    case saveFailed
}

/// The real macOS services, minus modal alerts: an error surfaced during a test
/// must never block the run waiting for someone to click OK.
private final class SilentPlatformManager: PlatformManager {
    private let real = MacOSPlatformManager.shared
    nonisolated var fileSystem: FileSystemService { real.fileSystem }
    nonisolated var checksum: ChecksumService { real.checksum }
    nonisolated var fileOperations: FileOperationsService { real.fileOperations }
    nonisolated var cameraDetection: CameraDetectionService { real.cameraDetection }
    nonisolated var supportsDragAndDrop: Bool { real.supportsDragAndDrop }

    func presentAlert(title: String, message: String) async {}
    func presentError(_ error: Error) async {}
    func openURL(_ url: URL) async -> Bool { false }
}
