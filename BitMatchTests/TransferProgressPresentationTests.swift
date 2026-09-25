import Foundation
import Combine
import Testing
@testable import BitMatch

/// UI plan step 4.9: one progress screen on Mac, iPad and iPhone. Each test
/// names the one-line production change ("Plant:") that must turn it red.
@MainActor
struct TransferProgressPresentationTests {
    private let primary = URL(fileURLWithPath: "/Volumes/Primary", isDirectory: true)
    private let secondary = URL(fileURLWithPath: "/Volumes/Secondary", isDirectory: true)

    private func progress(
        stage: ProgressStage,
        overall: Double,
        files: Int = 3,
        total: Int = 8,
        totals: [Int]? = nil,
        completed: [Int]? = nil,
        bytes: Int64? = nil
    ) -> OperationProgress {
        OperationProgress(
            overallProgress: overall,
            currentFile: "A001.MOV",
            filesProcessed: files,
            totalFiles: total,
            currentStage: stage,
            speed: nil,
            timeRemaining: nil,
            elapsedTime: nil,
            averageSpeed: nil,
            peakSpeed: nil,
            bytesProcessed: bytes,
            totalBytes: nil,
            stageProgress: nil,
            reusedCopies: nil,
            perDestinationTotals: totals,
            perDestinationCompleted: completed
        )
    }

    private func make(
        state: OperationState,
        isRunning: Bool = true,
        progress: OperationProgress?,
        destinations: [URL]? = nil,
        speed: String? = "90 MB/s",
        timeRemaining: String? = "3 min"
    ) -> TransferProgressPresentation {
        TransferProgressPresentation.make(
            state: state,
            isRunning: isRunning,
            progress: progress,
            sourceName: "A001",
            destinations: destinations ?? [primary, secondary],
            speed: speed,
            timeRemaining: timeRemaining,
            elapsed: nil,
            issueCount: 0,
            device: .mac
        )
    }

    /// The state stays `.inProgress` for the whole run; the stage comes from
    /// the engine, so a copy in progress is never "Preparing" with no bar.
    /// Plant: in `TransferProgressPresentation.phase`, add
    /// `if state == .inProgress { return .preparing }` before `switch stage`
    /// (the old Mac `TransferQueueView` mapping).
    @Test func runningCopyShowsBar() {
        let p = make(state: .inProgress, progress: progress(stage: .copying, overall: 0.25))

        #expect(p.phase == .copying)
        #expect(p.title == "Copying")
        #expect(p.title != "Preparing")
        #expect((p.fraction ?? 0) > 0)
        #expect(p.percentText == "25%")
        #expect(p.countText == "3 of 8 copied")
    }

    /// Plant: in `TransferProgressPresentation.make`, pass
    /// `canCancel: true` to `ProgressControls`.
    @Test func cancelUnavailableWhenIdle() {
        let idle = make(state: .notStarted, isRunning: false, progress: nil)
        let finished = make(
            state: .completed(OperationCompletionInfo(success: true, message: "Done")),
            isRunning: false,
            progress: nil
        )
        let running = make(state: .inProgress, progress: progress(stage: .copying, overall: 0.1))

        #expect(!idle.controls.canCancel)
        #expect(!finished.controls.canCancel)
        #expect(running.controls.canCancel)
    }

    /// Each backup shows its own copied fraction, never the overall one.
    /// Plant: in `TransferProgressPresentation.rows`, set
    /// `fraction = progress?.overallProgress` instead of `done / total`.
    @Test func destinationRowsUseOwnCounts() {
        let p = make(
            state: .inProgress,
            progress: progress(stage: .copying, overall: 0.4, totals: [4, 4], completed: [4, 1])
        )

        #expect(p.destinations.count == 2)
        #expect(p.destinations[0].fraction == 1.0)
        #expect(p.destinations[1].fraction == 0.25)
        #expect(p.destinations[0].countText == "4 of 4 copied")
        #expect(p.destinations[1].state == .copying)
    }

    /// Audit C1: a fully copied backup is "Copied", then "Verifying", and
    /// never "Done" or a verdict while the run is still going.
    /// Plant: in `TransferProgressPresentation.rows`, replace
    /// `state = phase == .verifying ? .verifying : .copied` with `state = .copied`.
    @Test func copiedBackupIsNotAVerdict() {
        let copying = make(
            state: .inProgress,
            progress: progress(stage: .copying, overall: 0.5, totals: [4, 4], completed: [4, 4])
        )
        let verifying = make(
            state: .inProgress,
            progress: progress(stage: .verifying, overall: 0.75, totals: [4, 4], completed: [4, 4])
        )

        #expect(copying.destinations.allSatisfy { $0.state == .copied && $0.stateLabel == "Copied" })
        #expect(verifying.destinations.allSatisfy { $0.state == .verifying && $0.stateLabel == "Verifying" })
        #expect(verifying.destinations.allSatisfy { !$0.symbol.contains("checkmark") })
    }

    /// Paused: Resume is the next step, and speed and time left are hidden.
    /// Plant: in `TransferProgressPresentation.make`, pass `speed: speed`
    /// instead of `speed: isPaused ? nil : speed`.
    @Test func pausedOffersResumeWithoutSpeed() {
        let paused = make(
            state: .paused(PauseInfo(
                pausedAt: Date(), currentFile: nil, filesProcessed: 3, totalFiles: 8,
                bytesProcessed: 0, reason: .lowBattery
            )),
            progress: progress(stage: .copying, overall: 0.2)
        )

        #expect(paused.phase == .paused)
        #expect(paused.tone == .paused)
        #expect(paused.controls.primary == .resume)
        #expect(paused.speed == nil)
        #expect(paused.timeRemaining == nil)
        #expect(paused.detail?.contains("battery") == true)
    }

    /// Speed leaves out paused time (one method on every platform).
    /// Plant: make `ProgressPresentationModel.noteResumed()` return at once
    /// (speed is then divided by wall-clock time, pause included).
    @Test func speedExcludesPausedTime() {
        var now = Date(timeIntervalSince1970: 1_000)
        let model = ProgressPresentationModel(clock: { now })
        model.reset()
        model.setFileCountTotal(100)

        now = now.addingTimeInterval(1)
        model.updateBytesProcessed(10_000_000)
        model.notePaused()
        now = now.addingTimeInterval(600)
        model.noteResumed()
        now = now.addingTimeInterval(1)
        model.updateBytesProcessed(10_000_000)

        let rate = model.averageBytesPerSecond ?? 0
        #expect(rate > 9_000_000)
        #expect(rate < 11_000_000)
    }

    /// Resuming (`.resuming`, then `.inProgress`) keeps the run's byte and
    /// file totals, so speed and time left stay right after a resume.
    /// Plant: in `SharedAppCoordinator.setupProgressPresentation`, replace the
    /// `if presentation.isTracking { … } else if …` block with
    /// `presentation.startProgressTracking()` (a reset on resume).
    @Test func resumeKeepsByteTotals() async throws {
        let folders = try CoordinatorFolders()
        defer { folders.cleanup() }
        let coordinator = SharedAppCoordinator(
            platformManager: RecordingPlatformManager(fileOperations: RecordingFileOperations()),
            transferJournal: LocalTransferJournal(fileURL: folders.journalURL),
            projectStore: InMemoryPhotographerJobStore()
        )
        coordinator.operationState = .inProgress
        coordinator.progress = progress(stage: .copying, overall: 0.25, files: 1, total: 4, bytes: 4_000)
        #expect(await waitUntil { coordinator.progressPresentation.totalBytesProcessed == 4_000 })

        coordinator.operationState = .paused(PauseInfo(
            pausedAt: Date(), currentFile: nil, filesProcessed: 1, totalFiles: 4,
            bytesProcessed: 4_000, reason: .userRequested
        ))
        coordinator.operationState = .resuming
        coordinator.operationState = .inProgress

        #expect(coordinator.progressPresentation.totalBytesProcessed == 4_000)
        #expect(coordinator.progressPresentation.fileCountTotal == 4)
        #expect(coordinator.progressPresentation.isTracking)
    }

    /// The redraw boundary: a progress tick changes `liveProgress`, which only
    /// the progress screen (and Compare) observe. The coordinator, which every
    /// shell observes, stays quiet, so the Mac window is not rebuilt per tick.
    /// Plant: in `SharedAppCoordinator.init`, add
    /// `liveProgress.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)`.
    @Test func progressTicksDoNotRedrawTheShell() throws {
        let folders = try CoordinatorFolders()
        defer { folders.cleanup() }
        let coordinator = SharedAppCoordinator(
            platformManager: RecordingPlatformManager(fileOperations: RecordingFileOperations()),
            transferJournal: LocalTransferJournal(fileURL: folders.journalURL),
            projectStore: InMemoryPhotographerJobStore()
        )
        var shellChanges = 0
        var liveChanges = 0
        let shell = coordinator.objectWillChange.sink { _ in shellChanges += 1 }
        let live = coordinator.liveProgress.objectWillChange.sink { _ in liveChanges += 1 }
        defer { shell.cancel(); live.cancel() }

        for files in 1...5 {
            coordinator.progress = progress(stage: .copying, overall: Double(files) / 10, files: files, total: 10)
        }

        #expect(liveChanges == 5)
        #expect(shellChanges == 0)
    }
}
