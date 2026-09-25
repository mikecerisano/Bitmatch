// SharedAppCoordinator.swift - Platform-agnostic app coordination
import Foundation

// Uses SharedLogger (shared file) for logging across platforms
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#endif

@MainActor
class SharedAppCoordinator: ObservableObject {
    
    // MARK: - Platform Manager
    private let platformManager: PlatformManager
    
    // MARK: - Services
    @Published var timingService = OperationTimingService()
    @Published var errorService = ErrorReportingService()
    @Published var stateService = OperationStateService()
    
    // MARK: - Published State
    @Published var currentMode: AppMode = .copyAndVerify
    @Published var verificationMode: VerificationMode = .standard {
        didSet { if oldValue != verificationMode { clearCompareOutcome() } }
    }
    /// The camera label for the next transfer: suggested from the card,
    /// remembered per camera and saved across launches (thesis decision).
    let cameraLabels: CameraLabelModel
    var cameraLabelSettings: CameraLabelSettings {
        get { cameraLabels.settings }
        set { cameraLabels.settings = newValue }
    }
    /// Camera settings for the next run only, used instead of
    /// `cameraLabelSettings` and cleared when that run starts. A prepared
    /// project card puts its job's folder recipe here, so the recipe never
    /// becomes the saved label.
    var projectRunCameraSettings: CameraLabelSettings?
    /// Saved across launches with the Mac's keys (decision: iPad and iPhone
    /// remember report settings too). A queued transfer's replay uses its
    /// record's settings for that run only and never saves them.
    @Published var reportSettings = ReportPrefs() {
        didSet { if !isReplayingQueuedTransfer { reportPrefsStore.save(reportSettings) } }
    }
    private let reportPrefsStore: ReportPrefsStore
    @Published var generateASCMHL: Bool = UserDefaults.standard.object(forKey: "BitMatchGenerateASCMHL") as? Bool ?? true {
        didSet { UserDefaults.standard.set(generateASCMHL, forKey: "BitMatchGenerateASCMHL") }
    }
    let transferJournal: LocalTransferJournal
    @Published private(set) var queueIsRunning = false
    @Published private(set) var queueMessage: String?
    @Published private(set) var isReplayingQueuedTransfer = false
    private var isProcessingQueue = false
    private var activeJournalRecordID: UUID?
    @Published var photographerJobViewModel: PhotographerJobViewModel
    /// Setup's Quick/Project choice. Held here, not in a view, so every
    /// Start (button, ⌘R) obeys it: choosing Project blocks Start until a
    /// card is prepared (thesis decision S-2).
    @Published var usesProjectWorkflow = false
    var photographerReportFinalizer: PhotographerReportFinalizer?

    // MARK: - Operation State
    @Published var isOperationInProgress = false
    /// Stored once, in `stateService` (Promise 2): the verdict on screen and
    /// pause/resume can never disagree. Writes are adopted as reported.
    var operationState: OperationState {
        get { stateService.currentState }
        set { stateService.adopt(newValue) }
    }
    /// Emits before each `operationState` change, as the stored property's
    /// `$operationState` publisher did.
    var operationStatePublisher: Published<OperationState>.Publisher { stateService.$currentState }
    /// The engine's latest progress. Stored in `liveProgress`, not published
    /// here: it changes about every 500 ms, and every shell observes this
    /// coordinator, so a published copy redrew each whole window per tick.
    /// Views that draw live progress observe `liveProgress` directly.
    var progress: OperationProgress? {
        get { liveProgress.progress }
        set { liveProgress.progress = newValue }
    }
    /// Deliberately not forwarded to this object's `objectWillChange`.
    let liveProgress = LiveProgressFeed()
    /// Smoothed progress for display (rolling speed, ETA, per-destination
    /// bars). Deliberately not forwarded to this object's `objectWillChange`:
    /// it ticks every 250 ms, so views observe it directly.
    let progressPresentation = ProgressPresentationModel()
    private var lastPresentedBytes: Int64 = 0
    /// Backups in the run being presented, so a later change of selection
    /// cannot mismatch the per-destination bars.
    private var presentedDestinationCount: Int?
    @Published var results: [ResultRow] = []
    @Published var currentOperation: FileOperation?

    // MARK: - Sub-coordinators
    private lazy var copyVerifyExecutor: CopyVerifyExecutor = {
        CopyVerifyExecutor(
            platformManager: platformManager,
            timingService: timingService,
            errorService: errorService,
            stateService: stateService,
            backgroundTaskService: backgroundTaskService
        )
    }()
    private(set) lazy var comparisonCoordinator: ComparisonCoordinator = {
        ComparisonCoordinator(platformManager: platformManager)
    }()

    enum CompletionExportError: LocalizedError {
        case noFinishedTransfer
        var errorDescription: String? {
            "No finished transfer to export. Run a transfer first; completed transfers stay available under History."
        }
    }
    
    // MARK: - File Selection State
    @Published var sourceURL: URL?
    @Published var destinationURLs: [URL] = []
    @Published var leftURL: URL? { // For folder comparison
        didSet { if oldValue != leftURL { clearCompareOutcome() } }
    }
    @Published var rightURL: URL? { // For folder comparison
        didSet { if oldValue != rightURL { clearCompareOutcome() } }
    }
    
    // MARK: - Camera Detection State
    @Published var detectedCamera: CameraCard?
    @Published var cameraDetectionInProgress = false
    
    // MARK: - Folder Info State (delegated to FolderInfoService)
    // One per coordinator (the app has one); a shared singleton let parallel
    // tests change each other's source analysis.
    @Published var folderInfoService = FolderInfoService()
    @Published var lastCompareStats: CompareStats?
    /// How the last compare for the current folders and mode ended. Compare
    /// reads this, not `operationState`, which transfers also write.
    @Published private(set) var lastCompareEnd: CompareRunEnd?
    /// True when the most recent operation was a compare, so the shared
    /// `operationState` it left behind is not shown as a transfer outcome.
    @Published private(set) var lastOperationWasCompare = false

    private func clearCompareOutcome() {
        lastCompareStats = nil
        lastCompareEnd = nil
    }

    // Convenience accessors for folder info (delegated to service)
    var sourceFolderInfo: EnhancedFolderInfo? { folderInfoService.sourceFolderInfo }
    var leftFolderInfo: EnhancedFolderInfo? { folderInfoService.leftFolderInfo }
    var rightFolderInfo: EnhancedFolderInfo? { folderInfoService.rightFolderInfo }
    var destinationFolderInfos: [URL: EnhancedFolderInfo] { folderInfoService.destinationFolderInfos }
    var folderInfoLoadingState: [URL: Bool] { folderInfoService.folderInfoLoadingState }
    
    private var cancellables = Set<AnyCancellable>()
    private var activeStartID: UUID?
    private var startCancellationRequested = false
    private var activeProjectCardID: UUID?

    // MARK: - iOS Background Task Service
    private let backgroundTaskService = IOSBackgroundTaskService.shared

    // Convenience accessors for iOS background state
    var backgroundTimeRemainingSeconds: Double? { backgroundTaskService.backgroundTimeRemainingSeconds }
    var isInBackground: Bool { backgroundTaskService.isInBackground }

    // MARK: - Initialization
    
    init(
        platformManager: PlatformManager,
        transferJournal: LocalTransferJournal? = nil,
        projectStore: (any PhotographerJobStore)? = nil,
        photographerJobViewModel: PhotographerJobViewModel? = nil,
        preferences: UserDefaults? = nil
    ) {
        self.platformManager = platformManager
        let environment = ProcessInfo.processInfo.environment
        let isTesting = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        let testJournalURL = isTesting ? FileManager.default.temporaryDirectory
            .appendingPathComponent("BitMatchTestJournal-\(UUID().uuidString).json") : nil
        // Tests get a throwaway suite so they never read or change the
        // user's saved settings; pass `preferences` to test persistence.
        let selectedPreferences: UserDefaults
        if let preferences {
            selectedPreferences = preferences
        } else if isTesting, let testDefaults = UserDefaults(suiteName: Self.testPreferencesSuite) {
            testDefaults.removePersistentDomain(forName: Self.testPreferencesSuite)
            selectedPreferences = testDefaults
        } else {
            selectedPreferences = .standard
        }
        self.reportPrefsStore = ReportPrefsStore(defaults: selectedPreferences)
        self.cameraLabels = CameraLabelModel(defaults: selectedPreferences)
        self.transferJournal = transferJournal ?? LocalTransferJournal(fileURL: testJournalURL)
        // The Mac passes its Core Data-backed, SFTP-capable view model so the
        // whole app has one; iPad and iPhone build a portable one here.
        if let photographerJobViewModel {
            self.photographerJobViewModel = photographerJobViewModel
        } else {
            let selectedProjectStore = projectStore ?? UserDefaultsPhotographerJobStore()
            self.photographerJobViewModel = PhotographerJobViewModel(
                store: selectedProjectStore,
                remoteBackupCoordinator: UnavailableRemoteProjectCoordinator(store: selectedProjectStore)
            )
        }
        self.reportSettings = reportPrefsStore.load()
        setupBindings()
        self.transferJournal.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // operationState lives in stateService; views observing this
        // coordinator must still refresh when it changes.
        stateService.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cameraLabels.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Views read the job view model through this coordinator too.
        self.photographerJobViewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        setupProgressPresentation()
        stateService.automaticPauseHandler = { [weak self] reason in
            Task { await self?.pauseOperation(reason: reason) }
        }
        // Default first launch to checksum verification; honor last-picked thereafter.
        if let saved = UserDefaults.standard.string(forKey: "lastVerificationMode"),
           let mode = VerificationMode.allCases.first(where: { $0.rawValue == saved }) {
            verificationMode = mode
        } else {
            verificationMode = .standard
        }
    }
    
    private static let testPreferencesSuite = "BitMatchTests.SharedAppCoordinator"

    #if os(iOS)
    convenience init() {
        self.init(platformManager: IOSPlatformManager.shared)
    }
    #endif
    
    #if os(macOS)
    convenience init() {
        self.init(platformManager: MacOSPlatformManager.shared)
    }
    #endif
    
    private func setupBindings() {
        // A prepared project card is tied to its source. `dropFirst()` skips
        // the replay Combine delivers on subscribing: without it every launch
        // reports "source changed to nil" and invalidates a card prepared
        // from the persisted store before anyone touched anything. Called
        // synchronously so a changed source is refused at once.
        $sourceURL
            .dropFirst()
            .sink { [weak self] url in
                guard let self else { return }
                self.photographerJobViewModel.sourceDidChange(to: url)
                // Suggest (or clear) the label for the new card. A queued
                // transfer's replay brings its own label.
                guard !self.isReplayingQueuedTransfer else { return }
                if let url {
                    self.cameraLabels.detectCameraWithMemory(at: url)
                } else {
                    self.cameraLabels.clearCameraLabel()
                }
            }
            .store(in: &cancellables)

        // Folder info for the source, and the detected camera card iPad shows.
        // Detection no longer delays the scan.
        $sourceURL
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateSource(url)
                }
                Task { @MainActor [weak self] in
                    await self?.detectCameraFromSource(url)
                }
            }
            .store(in: &cancellables)

        // Monitor left folder URL changes
        $leftURL
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateLeft(url)
                }
            }
            .store(in: &cancellables)

        // Monitor right folder URL changes
        $rightURL
            .sink { [weak self] url in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateRight(url)
                }
            }
            .store(in: &cancellables)

        // Monitor destination URLs changes
        $destinationURLs
            .sink { [weak self] urls in
                Task { @MainActor [weak self] in
                    await self?.folderInfoService.updateDestinations(urls)
                }
            }
            .store(in: &cancellables)

        // Forward folder info service changes to trigger UI updates
        folderInfoService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Persist verification mode across launches
        $verificationMode
            .sink { mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "lastVerificationMode")
            }
            .store(in: &cancellables)
    }

    // MARK: - Progress presentation

    /// Feeds `progressPresentation`: engine progress at most every 120 ms,
    /// and the smoothing timer while an operation runs.
    private func setupProgressPresentation() {
        liveProgress.$progress.compactMap { $0 }
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] prog in self?.presentProgress(prog) }
            .store(in: &cancellables)

        operationStatePublisher
            .sink { [weak self] state in
                guard let self else { return }
                let presentation = self.progressPresentation
                switch state {
                case .inProgress, .copying, .verifying, .resuming:
                    // One run is tracked once. Resume (`.resuming` then
                    // `.inProgress`) and stage changes keep the byte totals
                    // and speed samples; a new run stops tracking first
                    // (`executeOperation`), so it starts from zero.
                    if presentation.isTracking {
                        presentation.noteResumed()
                    } else if state != .resuming {
                        presentation.startProgressTracking()
                    }
                    if presentation.progressMessage == "Ready" {
                        presentation.setProgressMessage("Preparing transfer…")
                    }
                case .paused:
                    // Paused time is left out of speed and time remaining.
                    presentation.notePaused()
                case .completed, .failed, .cancelled:
                    presentation.stopProgressTracking()
                    self.lastPresentedBytes = 0
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func presentProgress(_ prog: OperationProgress) {
        let presentation = progressPresentation
        presentation.setFileCountTotal(prog.totalFiles)
        let destinationCount = presentedDestinationCount ?? destinationURLs.count
        // Time left is measured against the copy work actually planned: the
        // scanned source once per backup. The engine's `totalBytes` covers
        // one backup, and is a 1 GB guess when the source was not scanned.
        presentation.setPlannedTotalBytes(sourceFolderInfo.map { $0.totalSize * Int64(destinationCount) })
        presentation.fileCountCompleted = prog.filesProcessed
        if let totals = prog.perDestinationTotals, let completed = prog.perDestinationCompleted,
           totals.count == destinationCount, completed.count == destinationCount {
            presentation.setPerDestinationProgress(totals: totals, completed: completed)
        }
        if let name = prog.currentFile, !name.isEmpty { presentation.setCurrentFile(name) }
        if let reused = prog.reusedCopies { presentation.setReusedFileCopies(reused) }
        if let bytes = prog.bytesProcessed {
            let delta = bytes - lastPresentedBytes
            if delta > 0 { presentation.updateBytesProcessed(delta) }
            lastPresentedBytes = bytes
        }
        var message = prog.currentStage.displayName
        if let name = prog.currentFile, !name.isEmpty { message += " — \(name)" }
        presentation.setProgressMessage(message)
    }

    // MARK: - UI Helpers
    
    func showAlert(title: String, message: String) async {
        await platformManager.presentAlert(title: title, message: message)
    }
    
    func showError(_ error: Error) async {
        await platformManager.presentError(error)
    }
    
    // MARK: - File Selection Methods
    
    func selectSourceFolder() async {
        // A cancelled picker returns nil: preserve the existing selection.
        if let url = await platformManager.fileSystem.selectSourceFolder() {
            sourceURL = url
        }
    }
    
    func addDestinationFolder() async {
        let urls = await platformManager.fileSystem.selectDestinationFolders()
        var refusals: [String] = []
        for url in urls {
            if let refusal = addDestination(url) { refusals.append(refusal) }
        }
        // A picked system volume is refused with a reason, not silently.
        if !refusals.isEmpty {
            await showError(FileOperationError.unsafeOperation(refusals.joined(separator: "\n")))
        }
    }

    /// Adds a backup unless `BackupTargetPolicy` refuses it for `origin` or
    /// the same folder (by resolved path) is already chosen. Used by every
    /// platform's picker, Mac drag-and-drop, discovery and restore. Returns
    /// the refusal, which only a `.userChoice` caller shows; the automatic
    /// origins log it and move on.
    @discardableResult
    func addDestination(
        _ url: URL,
        origin: BackupTargetPolicy.Origin = .userChoice,
        facts: (URL) -> BackupTargetPolicy.VolumeFacts? = BackupTargetPolicy.VolumeFacts.read
    ) -> String? {
        if let refusal = BackupTargetPolicy.refusal(for: url, origin: origin, source: sourceURL, facts: facts) {
            SharedLogger.info("Backup refused (\(origin)): \(url.path): \(refusal)", category: .transfer)
            return refusal
        }
        let path = Self.resolvedPath(url)
        guard !destinationURLs.contains(where: { Self.resolvedPath($0) == path }) else { return nil }
        destinationURLs.append(url)
        return nil
    }

    /// Replaces every backup at once (the debug tools), keeping only what
    /// `BackupTargetPolicy` allows for a user's own pick.
    func replaceDestinations(with urls: [URL]) {
        destinationURLs = urls.filter { url in
            guard let refusal = BackupTargetPolicy.refusal(for: url, origin: .userChoice, source: sourceURL) else {
                return true
            }
            SharedLogger.info("Backup refused: \(url.path): \(refusal)", category: .transfer)
            return false
        }
    }

    func removeDestinationFolder(_ url: URL) {
        destinationURLs.removeAll { $0 == url }
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// True while the chosen source has not finished its folder scan. Start
    /// waits for it on every platform (the Mac's stricter rule, decided).
    var isAnalysingSource: Bool {
        guard let sourceURL else { return false }
        return folderInfoService.isAwaitingSourceInfo(for: sourceURL)
    }

    /// True while the left compare folder has not finished its scan.
    var isAnalysingLeft: Bool {
        guard let leftURL else { return false }
        return folderInfoService.isAwaitingLeftInfo(for: leftURL)
    }

    /// True while the right compare folder has not finished its scan.
    var isAnalysingRight: Bool {
        guard let rightURL else { return false }
        return folderInfoService.isAwaitingRightInfo(for: rightURL)
    }
    
    func selectLeftFolder() async {
        // A cancelled picker returns nil: preserve the existing selection.
        if let url = await platformManager.fileSystem.selectLeftFolder() {
            leftURL = url
        }
    }

    func selectRightFolder() async {
        // A cancelled picker returns nil: preserve the existing selection.
        if let url = await platformManager.fileSystem.selectRightFolder() {
            rightURL = url
        }
    }
    
    /// Completed, failed, and cancelled operations keep their (possibly
    /// partial) results visible instead of dropping back to setup.
    /// A compare shows its outcome inside the Compare screen; it is never
    /// the transfer outcome summary.
    var showsOutcomeSummary: Bool {
        guard !lastOperationWasCompare else { return false }
        switch operationState {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    // MARK: - Operation Control

    func startQueue() {
        guard !(isOperationInProgress && currentMode == .compareFolders) else {
            queueIsRunning = false
            queueMessage = "Finish or cancel the folder comparison, then choose Run queue."
            return
        }
        queueMessage = nil
        queueIsRunning = true
        Task { await processNextQueuedTransfer() }
    }

    func stopQueueAfterCurrentTransfer() { queueIsRunning = false }

    func retryTransfer(_ id: UUID, generateASCMHL: Bool? = nil) {
        do {
            _ = try transferJournal.requeue(id: id, generateASCMHL: generateASCMHL)
            startQueue()
        } catch { queueMessage = error.localizedDescription }
    }

    /// Indexes into `[source] + destinations` whose access expired. Empty means
    /// every location still resolves; unknown records report no stale locations.
    func reauthorizationStatus(id: UUID) -> [Int] {
        (try? transferJournal.staleResourceIndexes(id: id)) ?? []
    }

    /// Reconnects one expired location to the identical original folder.
    /// Throws when the pick is anything else, so another drive is never
    /// silently substituted. Earlier attempts and their evidence are kept.
    func reauthorizeTransfer(_ id: UUID, resourceIndex: Int, url: URL) throws {
        try transferJournal.reauthorize(id: id, resourceIndex: resourceIndex, newURL: url)
    }

    private func processNextQueuedTransfer() async {
        guard queueIsRunning, !isProcessingQueue, !isOperationInProgress, activeStartID == nil else { return }
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else {
            queueIsRunning = false
            queueMessage = "Queue paused. Open BitMatch and choose Run queue to continue."
            return
        }
        #endif
        guard let record = transferJournal.records.filter({ $0.state == .queued && $0.projectID == nil })
            .min(by: { $0.createdAt < $1.createdAt }) else {
            queueIsRunning = false
            return
        }
        guard !photographerJobViewModel.hasPreparedIngestAwaitingStart else {
            queueIsRunning = false
            queueMessage = "Finish or clear the prepared project card before running the queue."
            return
        }
        isProcessingQueue = true
        defer {
            isProcessingQueue = false
            isReplayingQueuedTransfer = false
            if queueIsRunning { Task { await self.processNextQueuedTransfer() } }
        }
        // The record's settings apply to this run only; the user's return
        // when it ends (UI plan §8 item 8).
        let userReportSettings = reportSettings
        let userCameraSettings = cameraLabelSettings
        do {
            let access = try transferJournal.prepareToRun(id: record.id)
            defer { access.release() }
            isReplayingQueuedTransfer = true
            cameraLabels.suspendsSaving = true
            defer {
                reportSettings = userReportSettings
                cameraLabelSettings = userCameraSettings
                cameraLabels.suspendsSaving = false
            }
            // Queued backups were the user's picks; the rule still applies,
            // since a record can predate it.
            if let refusal = access.destinationURLs.lazy.compactMap({
                BackupTargetPolicy.refusal(for: $0, origin: .userChoice, source: access.sourceURL)
            }).first {
                throw FileOperationError.unsafeOperation(refusal)
            }
            sourceURL = access.sourceURL
            destinationURLs = access.destinationURLs
            verificationMode = record.verificationMode
            cameraLabelSettings = record.cameraSettings
            reportSettings = record.reportSettings
            generateASCMHL = record.generateASCMHL
            currentMode = .copyAndVerify
            photographerReportFinalizer = nil
            activeProjectCardID = nil
            projectRunCameraSettings = nil
            await executeOperation(journalRecordID: record.id)
        } catch {
            queueIsRunning = false
            queueMessage = error.localizedDescription
            do {
                try transferJournal.markRunning(id: record.id)
                try transferJournal.interrupt(id: record.id, summary: error.localizedDescription)
            } catch {
                queueMessage = "Queue stopped: \(error.localizedDescription)"
            }
        }
    }

    func startOperation() async { await executeOperation(journalRecordID: nil) }

    private func executeOperation(journalRecordID: UUID?) async {
        // The run-only override applies to this attempt and never lingers.
        let runCameraSettings = projectRunCameraSettings ?? cameraLabelSettings
        projectRunCameraSettings = nil
        guard activeStartID == nil, !isOperationInProgress else { return }
        lastOperationWasCompare = false
        guard let sourceURL = sourceURL, !destinationURLs.isEmpty else {
            operationState = .failed
            updateProjectLifecycle(for: .failed)
            await platformManager.presentAlert(
                title: "Invalid Selection",
                message: "Please select a source folder and at least one destination folder."
            )
            return
        }

        let startID = UUID()
        activeStartID = startID
        startCancellationRequested = false
        isOperationInProgress = true
        activeJournalRecordID = nil
        defer {
            if activeStartID == startID {
                activeStartID = nil
                startCancellationRequested = false
                isOperationInProgress = false
                if queueIsRunning && !isProcessingQueue {
                    Task { await self.processNextQueuedTransfer() }
                }
            }
        }

        // iOS: Acquire security-scoped access BEFORE any FileManager operations
        // This is required for document picker URLs to work with FileManager on iOS
        // On macOS, these methods return true/no-op, so this is safe cross-platform
        let didStartSourceScope = platformManager.fileSystem.startAccessing(url: sourceURL)
        var destinationScopes: [URL: Bool] = [:]
        for destinationURL in destinationURLs {
            destinationScopes[destinationURL] = platformManager.fileSystem.startAccessing(url: destinationURL)
        }
        defer {
            if didStartSourceScope { platformManager.fileSystem.stopAccessing(url: sourceURL) }
            for (url, didStart) in destinationScopes where didStart {
                platformManager.fileSystem.stopAccessing(url: url)
            }
        }

        // Commit the immutable selection before copying. Failed persistence must
        // never leave a transfer running without a recoverable record.
        let recordID: UUID
        do {
            recordID = try journalRecordID ?? transferJournal.enqueue(
                sourceURL: sourceURL, destinationURLs: destinationURLs,
                verificationMode: verificationMode, cameraSettings: runCameraSettings,
                reportSettings: reportSettings, generateASCMHL: generateASCMHL,
                projectID: photographerReportFinalizer == nil ? nil : photographerJobViewModel.activeJob?.id
            )
            try transferJournal.markRunning(id: recordID)
            activeJournalRecordID = recordID
        } catch {
            queueIsRunning = false
            queueMessage = error.localizedDescription
            operationState = .failed
            updateProjectLifecycle(for: .failed)
            await platformManager.presentError(error)
            return
        }

        // Validate resolved destination paths before starting. Source-tree and
        // capacity checks run in the file operation after its manifest is built.
        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: sourceURL,
                destinations: destinationURLs,
                settings: runCameraSettings
            )
        } catch {
            try? transferJournal.interrupt(id: recordID, summary: error.localizedDescription)
            queueIsRunning = false
            operationState = .failed
            updateProjectLifecycle(for: .failed)
            await platformManager.presentError(error)
            return
        }

        guard activeStartID == startID, !startCancellationRequested else { return }

        // A new run starts its smoothed progress from zero, even if the last
        // run never reached a terminal state.
        progressPresentation.stopProgressTracking()
        lastPresentedBytes = 0
        operationState = .inProgress
        results = []
        progress = nil
        presentedDestinationCount = destinationURLs.count

        let config = CopyVerifyConfig(
            operationId: startID,
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            verificationMode: verificationMode,
            cameraLabelSettings: runCameraSettings,
            reportSettings: reportSettings,
            estimatedFiles: sourceFolderInfo?.fileCount ?? 100,
            estimatedBytes: sourceFolderInfo?.totalSize ?? 1_000_000_000,
            currentMode: currentMode,
            photographerReportFinalizer: photographerReportFinalizer,
            generateASCMHL: generateASCMHL
        )

        let callbacks = CopyVerifyCallbacks(
            onProgress: { [weak self] progressUpdate in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else { return }
                self.progress = progressUpdate
                if self.activeProjectCardID != nil {
                    self.photographerJobViewModel.updateProgressStage(progressUpdate.currentStage)
                }
            },
            onResult: { [weak self] result in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else { return }
                if let idx = self.results.firstIndex(where: { $0.path == result.path && $0.destination == result.destination }) {
                    self.results[idx] = result
                } else {
                    self.results.append(result)
                }
            },
            onStateChange: { [weak self] state in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else { return }
                self.operationState = state
                self.updateProjectLifecycle(for: state)
            },
            onAuthoritativeResults: { [weak self] allResults in
                guard let self,
                      self.activeStartID == startID,
                      !self.startCancellationRequested else {
                    throw CancellationError()
                }
                self.results = allResults
            }
        )

        do {
            currentOperation = try await copyVerifyExecutor.execute(config: config, callbacks: callbacks)
            if startCancellationRequested {
                try transferJournal.cancel(id: recordID, results: results)
            } else if case .completed(let info) = operationState {
                try transferJournal.finish(id: recordID, results: results, summary: info.message, hadIssues: !info.success)
                if transferJournal.records.first(where: { $0.id == recordID })?.state != .completed { queueIsRunning = false }
            } else {
                try transferJournal.interrupt(id: recordID, summary: "Transfer did not reach verified completion.", results: results)
                queueIsRunning = false
            }
        } catch {
            queueIsRunning = false
            do {
                if startCancellationRequested || error is CancellationError {
                    try transferJournal.cancel(id: recordID, results: results)
                } else {
                    try transferJournal.interrupt(id: recordID, summary: error.localizedDescription, results: results)
                }
            } catch {
                queueMessage = "Could not save transfer results: \(error.localizedDescription)"
                operationState = .failed
            }
        }
    }

    /// The one Start, for every platform's Start button and keyboard
    /// shortcut. A prepared project card starts through
    /// `startProjectOperation()`; with Project chosen and no card prepared
    /// nothing starts (S-2); any other transfer starts only when the
    /// readiness rule allows it; Compare runs the compare.
    func startCurrentMode() async {
        switch currentMode {
        case .copyAndVerify:
            if photographerJobViewModel.hasPreparedIngestAwaitingStart {
                await startProjectOperation()
            } else if usesProjectWorkflow {
                return
            } else if canStartOperation {
                await startOperation()
            }
        case .compareFolders:
            await compareFolders()
        case .masterReport:
            break
        }
    }

    /// Starts a prepared project ingest only after the ordinary transfer
    /// preflight is safe. The project finalizer remains attached through
    /// verification, so completion retains its local evidence on every
    /// platform, and the run uses the job's folder recipe.
    @discardableResult
    func startProjectOperation() async -> Bool {
        guard activeStartID == nil, !isOperationInProgress,
              operationReadinessAssessment.isReady,
              photographerJobViewModel.hasPreparedIngestAwaitingStart,
              let jobID = photographerJobViewModel.activeJob?.id,
              let cardID = photographerJobViewModel.activeCard?.id,
              photographerJobViewModel.preliminaryAnalysis != nil else {
            return false
        }
        guard photographerJobViewModel.beginIngest(
            destinationCount: destinationURLs.count,
            sourceURL: sourceURL,
            verificationMode: verificationMode
        ) else {
            return false
        }

        photographerReportFinalizer = { [weak photographerJobViewModel, jobID, cardID] results in
            guard let photographerJobViewModel,
                  photographerJobViewModel.activeJob?.id == jobID,
                  photographerJobViewModel.activeCard?.id == cardID,
                  let state = photographerJobViewModel.activeCard?.localState,
                  state == .copying || state == .verifying else {
                throw PhotographerReportError.cardNotReady
            }
            return try photographerJobViewModel.completeIngest(results: results)
        }
        activeProjectCardID = cardID
        // The job's folder recipe applies to this run only; the saved label
        // stays the user's. (Until now only the Mac applied it.)
        if let renderedRecipe = photographerJobViewModel.renderedRecipe {
            projectRunCameraSettings = PhotographerDestinationResolver.operationSettings(
                base: cameraLabelSettings,
                renderedRecipe: renderedRecipe
            )
        }
        await startOperation()
        // Every terminal state clears `activeProjectCardID`. A start that
        // returned without one must not leave the card copying.
        if activeProjectCardID == cardID, !isOperationInProgress {
            photographerJobViewModel.operationFailed()
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        }
        return true
    }

    func cancelOperation() {
        queueIsRunning = false
        if activeStartID != nil {
            startCancellationRequested = true
        }
        copyVerifyExecutor.cancel()
        if currentMode == .compareFolders {
            comparisonCoordinator.requestCancellation()
        }

        // Report cancellation to error service
        let context = ErrorContext.general(operation: "File Operation", stage: "Cancelled")
        errorService.reportWarning("Operation cancelled by user", context: context)
        errorService.completeErrorTracking()
        stateService.cancelOperation()
        NotificationCenter.default.post(name: .operationCancelledByUser, object: nil)
        
        operationState = .cancelled
        updateProjectLifecycle(for: .cancelled)
    }
    
    func pauseOperation(reason: PauseInfo.PauseReason = .userRequested) async {
        guard stateService.currentState.canPause else { return }
        
        // Pause the underlying file operations
        await platformManager.fileOperations.pauseOperation()

        // The run may have finished while the engine paused; a finished run
        // stays finished and offers no Resume.
        guard stateService.currentState.canPause else { return }

        // Update state service with current progress
        stateService.pauseOperation(reason: reason, currentProgress: progress)
        
        // Update our operation state to match
        operationState = stateService.currentState
        
        // Update capabilities
        stateService.updateCapabilities(canPause: false, canResume: true)
        SharedLogger.info("Operation paused (\(reason))", category: .transfer)
    }
    
    func resumeOperation() async {
        guard stateService.currentState.canResume else { return }
        
        // Check if resume is recommended
        if let recommendation = stateService.getResumeRecommendation(),
           !recommendation.shouldResume {
            await platformManager.presentAlert(
                title: "Resume Not Recommended",
                message: recommendation.reason
            )
            return
        }
        
        // Resume the underlying file operations
        await platformManager.fileOperations.resumeOperation()
        
        // Update state service
        if stateService.resumeOperation() {
            operationState = stateService.currentState
            
            // Update capabilities
            stateService.updateCapabilities(canPause: true, canResume: false)
            SharedLogger.info("Operation resumed", category: .transfer)
        }
    }
    
    private func updateProjectLifecycle(for state: OperationState) {
        guard activeProjectCardID != nil else { return }
        switch state {
        case .verifying:
            photographerJobViewModel.updateProgressStage(.verifying)
        case .completed(let info):
            if !info.success { photographerJobViewModel.operationFailed() }
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        case .failed:
            photographerJobViewModel.operationFailed()
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        case .cancelled:
            photographerJobViewModel.cancelIngest()
            activeProjectCardID = nil
            photographerReportFinalizer = nil
        default:
            break
        }
    }

    // MARK: - Camera Detection
    
    /// The camera card iPad shows next to the source. The label itself comes
    /// from `cameraLabels`, the same memory-aware path as the Mac.
    private func detectCameraFromSource(_ url: URL?) async {
        guard let url else {
            detectedCamera = nil
            cameraDetectionInProgress = false
            return
        }
        cameraDetectionInProgress = true
        detectedCamera = nil

        let result = await platformManager.cameraDetection.detectCamera(from: url)

        // A newer source may have been chosen while detection ran.
        guard sourceURL == url else { return }
        detectedCamera = result.cameraCard
        cameraDetectionInProgress = false
    }
    
    // MARK: - Folder Comparison (delegated to ComparisonCoordinator)

    func compareFolders() async {
        guard currentMode == .compareFolders else { return }
        guard let left = leftURL, let right = rightURL else {
            await platformManager.presentAlert(
                title: "Invalid Selection",
                message: "Please select both folders to compare."
            )
            return
        }

        // Every entry point (buttons, ⌘R, tests) gets the same block as the
        // screen: a folder compared with itself or its own parent or child
        // would report a false match.
        if let block = CompareBlock.check(left: left, right: right) {
            await platformManager.presentAlert(title: "Can't compare these folders", message: block.message)
            return
        }

        guard !isOperationInProgress else { return }
        let comparedMode = verificationMode
        isOperationInProgress = true
        lastOperationWasCompare = true
        operationState = .inProgress
        results = []
        clearCompareOutcome()
        errorService.clearCurrentErrors()
        progress = OperationProgress(
            overallProgress: 0.0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: 0,
            currentStage: .preparing,
            speed: nil,
            timeRemaining: nil
        )

        do {
            let stats = try await comparisonCoordinator.compareFolders(
                left: left,
                right: right,
                verificationMode: comparedMode,
                onProgress: { [weak self] prog in
                    self?.progress = prog
                }
            )
            if Task.isCancelled || comparisonCoordinator.isCancellationRequested {
                throw CancellationError()
            }
            guard leftURL == left, rightURL == right, verificationMode == comparedMode else {
                isOperationInProgress = false
                operationState = .notStarted
                progress = nil
                return
            }
            self.lastCompareStats = stats
            lastCompareEnd = .completed
            isOperationInProgress = false
            let message: String
            if stats.isClean {
                message = CompareCheckPlan.make(for: comparedMode).verifiesContents
                    ? "Folders match"
                    : "Sizes match, not verified"
            } else {
                var issues: [String] = []
                if stats.mismatchedCount > 0 { issues.append("\(stats.mismatchedCount) mismatched") }
                if stats.onlyInLeftCount > 0 { issues.append("\(stats.onlyInLeftCount) only in source") }
                if stats.onlyInRightCount > 0 { issues.append("\(stats.onlyInRightCount) only in destination") }
                message = "Comparison found differences: \(issues.joined(separator: ", "))"
            }
            operationState = .completed(OperationCompletionInfo(success: stats.isClean, message: message))
            return
        } catch is CancellationError {
            isOperationInProgress = false
            operationState = .cancelled
            lastCompareEnd = .cancelled
            return
        } catch {
            isOperationInProgress = false
            operationState = .failed
            lastCompareEnd = .failed(error.localizedDescription)
            await platformManager.presentError(error)
            return
        }
    }
    
    // MARK: - Completion Export (same record as history)

    /// Builds the completion export from the finished transfer's journal record:
    /// authoritative per-file results, verification mode, project provenance, and
    /// the ASC MHL request flag. Callers present real save/share UI and surface
    /// thrown errors instead of opening a temporary summary elsewhere.
    func completionExportDocument(asCSV: Bool) throws -> TransferHistoryDocument {
        guard let id = activeJournalRecordID,
              let record = transferJournal.records.first(where: { $0.id == id }),
              record.state != .queued, record.state != .running else {
            throw CompletionExportError.noFinishedTransfer
        }
        return try TransferHistoryDocument(record: record, asCSV: asCSV)
    }
    
    // MARK: - Mode Management

    /// Decision C-2: no mode switch while anything runs, on any platform.
    var isModeSwitchLocked: Bool {
        ModeSwitchPolicy.isLocked(isOperationInProgress: isOperationInProgress, queueIsRunning: queueIsRunning)
    }

    func switchMode(to mode: AppMode) {
        guard !isModeSwitchLocked else { return }
        currentMode = mode
    }

    /// The journal record of the transfer the outcome screen shows: it gives
    /// Retry, Export and the run's duration. Nil after `resetForNewOperation()`.
    var outcomeRecord: LocalTransferRecord? {
        guard let id = activeJournalRecordID else { return nil }
        return transferJournal.records.first { $0.id == id }
    }

    /// "New transfer" on the outcome screen, on every platform (decision
    /// O-1): the next card usually goes to the same backups, and keeping the
    /// old source risks copying the same card again by accident.
    func startNewTransfer() {
        resetForNewOperation()
        sourceURL = nil
    }

    func resetForNewOperation() {
        results = []
        progress = nil
        progressPresentation.reset()
        lastPresentedBytes = 0
        presentedDestinationCount = nil
        operationState = .notStarted
        currentOperation = nil
        activeJournalRecordID = nil
    }

    func togglePause() async {
        if canPause {
            await pauseOperation()
        } else if canResume {
            await resumeOperation()
        }
    }

    func saveVerificationMode() {
        UserDefaults.standard.set(verificationMode.rawValue, forKey: "lastVerificationMode")
    }

    // MARK: - Completion State (derived from OperationState)

    var completionState: CompletionState {
        switch operationState {
        case .completed(let info):
            if info.success {
                return .success(message: info.message)
            } else {
                return .issues(message: info.message)
            }
        case .failed:
            return .failed(message: "Operation failed")
        case .inProgress, .copying, .verifying, .resuming:
            return .inProgress
        case .cancelled:
            return .cancelled(message: "Operation cancelled by user")
        case .idle, .notStarted, .paused:
            return .idle
        }
    }

    // MARK: - Computed Properties

    var canStartOperation: Bool {
        switch currentMode {
        case .copyAndVerify:
            return operationReadinessAssessment.isReady && !isOperationInProgress
        case .compareFolders:
            guard let leftURL, let rightURL, !isOperationInProgress else { return false }
            return CompareBlock.check(left: leftURL, right: rightURL) == nil
        case .masterReport:
            return currentOperation != nil && !isOperationInProgress
        }
    }
    
    var progressPercentage: Double {
        return progress?.overallProgress ?? 0.0
    }
    
    var formattedSpeed: String? {
        return progress?.formattedSpeed
    }
    
    var formattedTimeRemaining: String? {
        return progress?.formattedTimeRemaining
    }
    
    var currentStage: ProgressStage {
        return progress?.currentStage ?? .idle
    }
    
    // MARK: - Timing Computed Properties
    
    var operationDuration: String? {
        return timingService.currentTiming?.formattedDuration
    }
    
    var averageOperationSpeed: String? {
        return timingService.currentTiming?.formattedSpeed
    }
    
    var operationHistory: [OperationTiming] {
        return timingService.timingHistory
    }
    
    var operationStats: OperationHistoryStats? {
        return timingService.getHistoryStats()
    }
    
    // MARK: - Error Computed Properties
    
    var currentErrors: [ErrorReport] {
        return errorService.currentErrors
    }
    
    var errorSummary: ErrorSummary? {
        return errorService.errorSummary
    }
    
    var hasErrors: Bool {
        return !errorService.currentErrors.isEmpty
    }
    
    var hasCriticalErrors: Bool {
        return errorService.getCriticalErrors().count > 0
    }
    
    var errorCount: Int {
        return errorService.currentErrors.filter { $0.category != .warning }.count
    }
    
    var warningCount: Int {
        return errorService.currentErrors.filter { $0.category == .warning }.count
    }
    
    // MARK: - Pause/Resume Computed Properties
    
    var canPause: Bool {
        return stateService.currentState.canPause
    }
    
    var canResume: Bool {
        return stateService.currentState.canResume
    }
    
    var isPaused: Bool {
        return stateService.currentState.isPaused
    }
    
    var pauseResumeCapabilities: PauseResumeCapabilities {
        return stateService.pauseResumeCapabilities
    }
    
    var savedOperations: [SavedOperationState] {
        return stateService.savedOperations
    }
    
    // MARK: - Folder Info Computed Properties

    func getFolderInfo(for url: URL) -> EnhancedFolderInfo? {
        return folderInfoService.getFolderInfo(for: url)
    }

    func isFolderInfoLoading(for url: URL) -> Bool {
        return folderInfoService.isFolderInfoLoading(for: url)
    }
    
    var sourceFolderSummary: String {
        guard let info = sourceFolderInfo else { return "No folder selected" }
        return "\(info.formattedFileCount) files • \(info.formattedSize)"
    }
    
    var destinationsSummary: String {
        guard !destinationURLs.isEmpty else { return "No destinations selected" }
        let totalCapacity = destinationFolderInfos.values.compactMap { 
            getDriveCapacity(for: $0.url) 
        }.reduce(0, +)
        
        if totalCapacity > 0 {
            let formattedCapacity = ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
            return "\(destinationURLs.count) destination\(destinationURLs.count == 1 ? "" : "s") • ~\(formattedCapacity) available"
        } else {
            return "\(destinationURLs.count) destination\(destinationURLs.count == 1 ? "" : "s")"
        }
    }
    
    private func getDriveCapacity(for url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let cap = values.volumeAvailableCapacity {
                return Int64(cap)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // Get folder info with type hints for professional display
    func getFolderDisplayInfo(for url: URL) -> FolderDisplayInfo? {
        guard let enhancedInfo = getFolderInfo(for: url) else { return nil }
        
        // Convert to base FolderInfo for compatibility
        let baseInfo = FolderInfo(
            url: enhancedInfo.url,
            fileCount: enhancedInfo.fileCount,
            totalSize: enhancedInfo.totalSize,
            lastModified: enhancedInfo.lastModified,
            isInternalDrive: enhancedInfo.isInternalDrive
        )
        
        let driveType = getDriveType(for: url)
        let availableSpace = getDriveCapacity(for: url)
        let isLoading = isFolderInfoLoading(for: url)
        
        return FolderDisplayInfo(
            baseInfo: baseInfo,
            driveType: driveType,
            availableSpace: availableSpace,
            isLoading: isLoading
        )
    }
    
    private func getDriveType(for url: URL) -> DriveType {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsInternalKey,
                .volumeNameKey
            ])
            
            if values.volumeIsRemovable == true || values.volumeIsEjectable == true {
                // Check if it's likely a camera card based on volume name
                if let name = values.volumeName?.lowercased() {
                    if name.contains("untitled") || name.hasPrefix("no name") || 
                       name.contains("cf") || name.contains("sd") {
                        return .cameraCard
                    }
                }
                return .externalDrive
            } else if values.volumeIsInternal == false {
                return .networkDrive
            } else {
                return .internalDrive
            }
        } catch {
            return .unknown
        }
    }
    
    // MARK: - Enhanced Folder Info Helpers
    
    /// Get a detailed summary for source folder including file types
    var sourceDetailedSummary: String? {
        guard let info = sourceFolderInfo else { return nil }
        var parts = [info.formattedFileCount + " files", info.formattedSize]
        
        if let topType = info.topFileTypes.first {
            parts.append("\(topType.count) \(topType.type) files")
        }
        
        return parts.joined(separator: " • ")
    }
    
    /// Get file type breakdown for source folder
    var sourceFileTypesBreakdown: [(type: String, count: Int)] {
        return sourceFolderInfo?.topFileTypes ?? []
    }
    
    /// Whether a transfer may start, and why not. One rule on every platform
    /// (thesis decision): the Mac's stricter check, with the runtime's space
    /// margin. See `OperationReadinessAssessment.assess`.
    var operationReadinessAssessment: OperationReadinessAssessment {
        OperationReadinessAssessment.assess(
            source: sourceURL,
            sourceBytes: sourceFolderInfo?.totalSize,
            sourceFileCount: sourceFolderInfo?.fileCount,
            isAnalysingSource: isAnalysingSource,
            destinations: destinationURLs,
            settings: cameraLabelSettings,
            verificationMode: verificationMode,
            availableBytes: { self.getDriveCapacity(for: $0) }
        )
    }
    
    /// Get source folder metadata summary for professional display
    var sourceFolderMetadata: FolderMetadataSummary? {
        guard let info = sourceFolderInfo else { return nil }
        
        return FolderMetadataSummary(
            fileCount: info.fileCount,
            totalSize: info.totalSize,
            averageFileSize: info.averageFileSize,
            largestFile: info.largestFile,
            fileTypeBreakdown: info.topFileTypes,
            dateRange: info.dateRangeDescription,
            driveType: getDriveType(for: info.url),
            lastModified: info.lastModified
        )
    }
}

struct CompareStats: Equatable {
    let onlyInLeftCount: Int
    let onlyInRightCount: Int
    let commonCount: Int
    let mismatchedCount: Int
    /// Relative paths behind the counts, sorted for stable display and export.
    /// Retained so a reported difference (e.g. one destination-only item from a
    /// camera-card offload) names the file instead of ending at a count.
    let onlyInLeftPaths: [String]
    let onlyInRightPaths: [String]
    let mismatchedPaths: [String]

    init(
        onlyInLeftCount: Int,
        onlyInRightCount: Int,
        commonCount: Int,
        mismatchedCount: Int,
        onlyInLeftPaths: [String] = [],
        onlyInRightPaths: [String] = [],
        mismatchedPaths: [String] = []
    ) {
        self.onlyInLeftCount = onlyInLeftCount
        self.onlyInRightCount = onlyInRightCount
        self.commonCount = commonCount
        self.mismatchedCount = mismatchedCount
        self.onlyInLeftPaths = onlyInLeftPaths
        self.onlyInRightPaths = onlyInRightPaths
        self.mismatchedPaths = mismatchedPaths
    }

    /// True only when both folders contain the same files with matching content.
    var isClean: Bool {
        onlyInLeftCount == 0 && onlyInRightCount == 0 && mismatchedCount == 0
    }
}

// MARK: - Supporting Types for Enhanced Folder Display

struct OperationReadinessAssessment {
    let isReady: Bool
    /// Everything in the way, including "not chosen yet".
    let issues: [String]
    let warnings: [String]
    /// Only real findings: `issues` without the two "not chosen yet" lines,
    /// which the setup screens show as the next step instead.
    var blockingIssues: [String] = []
    /// The source scan has not finished. Not an issue (nothing is wrong),
    /// but Start waits for it.
    var isAnalysing = false
    
    var hasIssues: Bool { !issues.isEmpty }
    var hasWarnings: Bool { !warnings.isEmpty }
    
    var statusIcon: String {
        if !isReady { return "exclamationmark.triangle.fill" }
        if hasWarnings { return "exclamationmark.triangle" }
        return "checkmark.circle.fill"
    }
    
    var statusColor: Color {
        if !isReady { return .red }
        if hasWarnings { return .orange }
        return .green
    }
    
    var statusMessage: String {
        if !isReady && issues.isEmpty && isAnalysing {
            return "Analyzing source…"
        }
        if !isReady {
            return "Cannot start: \(issues.joined(separator: ", "))"
        }
        if hasWarnings {
            return "Ready with warnings: \(warnings.joined(separator: ", "))"
        }
        return "Ready to start"
    }
}

extension OperationReadinessAssessment {
    static let noSourceIssue = "No source folder selected"
    static let noDestinationIssue = "No destination folders selected"

    /// The one readiness rule. Pure: free space comes from `availableBytes`
    /// (nil when a destination's capacity cannot be read).
    ///
    /// - Blocks until a source and a backup are chosen, while the source is
    ///   still being analysed, on duplicate, protected or unsafe backups, on
    ///   resolved-folder conflicts, and when a backup's free space is not more
    ///   than the source size plus `SafetyValidator.requiredHeadroomBytes`
    ///   (exactly what the copy itself refuses, so "Ready" cannot fail at
    ///   start). Space is checked for every backup whose capacity is readable.
    /// - Warns in Quick mode and when the source needs more than 70% of a
    ///   backup's free space.
    static func assess(
        source: URL?,
        sourceBytes: Int64?,
        sourceFileCount: Int?,
        isAnalysingSource: Bool,
        destinations: [URL],
        settings: CameraLabelSettings,
        verificationMode: VerificationMode,
        availableBytes: (URL) -> Int64?
    ) -> OperationReadinessAssessment {
        guard let source else {
            return OperationReadinessAssessment(
                isReady: false,
                issues: [noSourceIssue],
                warnings: []
            )
        }

        var setupIssues: [String] = []
        var blocking: [String] = []
        var warnings: [String] = []

        if destinations.isEmpty {
            setupIssues.append(noDestinationIssue)
        }

        let uniqueDestinationPaths = Set(destinations.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        if uniqueDestinationPaths.count != destinations.count {
            blocking.append("Destination folders must be unique")
        }

        for destination in destinations {
            if SafetyValidator.isProtectedSystemPath(destination) {
                blocking.append("\(destination.lastPathComponent): System folders cannot be used as destinations")
            } else if let refusal = BackupTargetPolicy.refusal(for: destination, origin: .userChoice, source: source) {
                blocking.append(refusal)
            } else if let issue = SafetyValidator.destinationSafetyIssue(source: source, destination: destination) {
                blocking.append("\(destination.lastPathComponent): \(issue)")
            }
        }

        do {
            try SafetyValidator.validateResolvedDestinationRoots(
                source: source,
                destinations: destinations,
                settings: settings
            )
        } catch {
            blocking.append(error.localizedDescription)
        }

        if verificationMode == .quick {
            warnings.append("Quick mode only checks file size. Standard SHA-256 is safer for production transfers.")
        }

        if let sourceBytes {
            for destination in destinations {
                guard let available = availableBytes(destination) else { continue }
                // The copy needs more than source + headroom free.
                if available - SafetyValidator.requiredHeadroomBytes <= sourceBytes {
                    blocking.append("Insufficient space on \(destination.lastPathComponent)")
                } else if available > 0, Double(sourceBytes) / Double(available) > 0.7 {
                    warnings.append("Limited space on \(destination.lastPathComponent)")
                }
            }
        }

        let issues = setupIssues + blocking
        return OperationReadinessAssessment(
            isReady: issues.isEmpty && !isAnalysingSource,
            issues: issues,
            warnings: warnings,
            blockingIssues: blocking,
            isAnalysing: isAnalysingSource
        )
    }
}

struct FolderMetadataSummary {
    let fileCount: Int
    let totalSize: Int64
    let averageFileSize: Int64
    let largestFile: (name: String, size: Int64)?
    let fileTypeBreakdown: [(type: String, count: Int)]
    let dateRange: String
    let driveType: DriveType
    let lastModified: Date
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedAverageSize: String {
        ByteCountFormatter.string(fromByteCount: averageFileSize, countStyle: .file)
    }
    
    var formattedLargestFile: String? {
        guard let largest = largestFile else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: largest.size, countStyle: .file)
        return "\(largest.name) (\(size))"
    }
    
    var primaryFileType: String? {
        return fileTypeBreakdown.first?.type
    }
    
    var diversityScore: String {
        let typeCount = fileTypeBreakdown.count
        if typeCount <= 1 { return "Uniform" }
        if typeCount <= 3 { return "Mixed" }
        return "Diverse"
    }
}
