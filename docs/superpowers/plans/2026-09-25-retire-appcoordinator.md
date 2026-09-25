# Retire AppCoordinator Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans (or subagent-driven-development) to carry this out task by task. Steps use checkbox (`- [ ]`) syntax. Each task must build the `BitMatch` (macOS) and `BitMatch-iPad` schemes and pass `BitMatchTests` before it is committed.

**Goal:** Delete `BitMatch/App/AppCoordinator.swift`. Mac views bind to `SharedAppCoordinator` directly, as iPad and iPhone already do. This is step 3 of the plan in [docs/THESIS.md](../../THESIS.md) and serves promise 5, "One app everywhere".

**Status:** Written without Xcode, first against `main` at `9ff3f85`. **Updated 2026-09-25 against `main` at `1465194`** (see §0) and carried out on branch `cloud/retire-appcoordinator`, one commit per task below (Tasks 0–10, with 4a and 6a/6b). Nothing on that branch has been compiled or run; a Mac session must build both schemes and run the tests for each commit, and do the manual checks each task lists. Line numbers refer to `1465194`.

**Architecture:** Today macOS runs two coordinators. `SharedAppCoordinator` owns the engine, operation state, results, journal and queue. `AppCoordinator` wraps it and owns five Mac-only view models (`ProgressViewModel`, `FileSelectionViewModel`, `CameraLabelViewModel`, `SettingsViewModel`, and its own `PhotographerJobViewModel`) plus `CameraCardDetectionService`. It keeps them in step with 17 Combine subscriptions and a block of imperative copies in `startOperation()`. After this plan, `SharedAppCoordinator` is the only state owner on every platform. Mac-only abilities (SFTP, the drive benchmark, volume monitoring and auto-selecting a detected card, Mac window sizing) move into small Mac-only companions that read from and write to `SharedAppCoordinator`. None of them keeps its own copy of shared state.

**Out of scope:** merging the Mac and iPad view files (thesis step 4), Core Data vs. JSON job storage, deleting `DriveBenchmarkService` (thesis step 5 decision), and Swift 6. This plan should not make any of those harder.

---

## 0. What changed since the first draft

- **Thesis step 2 is done.** `operationState` is no longer a stored `@Published` property: it reads and writes `stateService.currentState` (`SharedAppCoordinator.swift:55-58`), and `operationStatePublisher` (`:61`) replaced `$operationState`. S14 and S16 below now subscribe to `operationStatePublisher`. `stateService.objectWillChange` is forwarded to the coordinator (`:158`).
- **Compare screen landed (UI plan 4.1, 4.2).** `BitMatch/Views/CompareFoldersView.swift` is now a 103-line adapter over the shared `CompareScreen`. It reads `fileSelectionViewModel.leftURL`/`rightURL`/`left|rightFolderInfo`/`isFetchingLeft|RightInfo`, observes `FileSelectionViewModel` and `SharedAppCoordinator` directly, and starts through `startIfReady` (also used by ⌘R). `SharedAppCoordinator` gained `lastCompareEnd`, `lastOperationWasCompare`, and a `CompareBlock` check in `compareFolders()` and `canStartOperation`. Retiring AppCoordinator touches this adapter for **bindings only**; `Shared/Views/Compare/` and `ComparePresentation.swift` are owned by the compare-polish work.
- **Advanced options landed (UI plan 4.6).** `TransferOptionsView` is `MacTransferOptionsAdapter` over the shared `TransferOptionsSection`. It observes the shared coordinator, the label VM and the settings VM directly.
- **History screen landed.** `ContentView` presents the shared `TransferLibraryView(coordinator: shared, journal:)`. I2 (the `onAppear` prefs push) is still there.
- **Next-step glow landed.** `TransferPlanPresentation.nextStep` drives `HorizontalFlowView(nextStep:)`. The Mac `CopyAndVerifyView.readinessIssues` returns nothing until a source is chosen.
- **Mode lock.** `SharedAppCoordinator.switchMode` obeys `ModeSwitchPolicy` (running operation *or* running queue). `AppCoordinator.switchMode` checks only `isOperationInProgress`; `ContentView` hides the selector with the stricter policy.
- **Decisions (thesis, 2026-09-25)** settle §2: §2.3 uses **source size + 1 GB** (the runtime rule in `SafetyValidator.validateAvailableSpace`), not +100 MB; §2.4 and §2.5 are accepted for iPad and iPhone. `DriveBenchmarkService` will be deleted in step 5, so Task 3's `TransferEstimateModel` is its only caller and a temporary home. "Choosing Project blocks Start" and "restore last backups only when all are mounted" are step 4 UI decisions; this plan does not implement them.
- **Parity coverage.** `BitMatchTests/PlatformVerdictParityTests.swift` already runs the same card through the Mac and an iOS-shaped platform manager and compares rows and verdict. Task 0 therefore ports only the coordinator-level behaviour.
- **DevModeManager.** Its `SharedAppCoordinator` overloads are inside `#if os(iOS)` in a Mac-only file, so they never compile. Task 9 rewrites the Mac overloads instead of reusing them.
- **Also requested:** the Mac Preferences "Generate PDF" and "Generate CSV" checkboxes are deleted (Task 4a). The report writer ignores both flags: with reports on it always writes the CSV, and the PDF on macOS.

## 1. Inventory

### 1.1 What `AppCoordinator` owns

| Member | Lines | Kind | Destination |
|---|---|---|---|
| `sharedCoordinator` | 17 | the real core | Becomes the only coordinator |
| `progressViewModel: ProgressViewModel` | 22 | mirrored VM #1 | `Shared/`, owned by `SharedAppCoordinator` (Task 7) |
| `fileSelectionViewModel: FileSelectionViewModel` | 23 | mirrored VM #2 | Selection → `SharedAppCoordinator`; Mac volume/bookmark/recents parts → `MacVolumeAccessModel` (Task 6a) |
| `cameraLabelViewModel: CameraLabelViewModel` | 24 | mirrored VM #3 | `Shared/`, owned by `SharedAppCoordinator` (Task 5) |
| `settingsViewModel: SettingsViewModel` | 25 | mirrored VM #4 | `SharedAppCoordinator.reportSettings` + `ReportPrefsStore` (Task 4) |
| `photographerJobViewModel` (Core Data store, SFTP-capable) | 27 | mirrored VM #5 | Injected into `SharedAppCoordinator` (Task 1) |
| `cameraDetectionService: CameraCardDetectionService` | 26 | Mac service | `MacCameraAutoSourceController` (Task 6a) |
| `currentMode` | 37 | duplicate of `sharedCoordinator.currentMode`, copied only at start | Delete; use shared `currentMode` / `switchMode` (Task 8) |
| `timeEstimate`, `isCalculatingEstimate`, `updateTimeEstimate()` | 38–39, 405–426 | Mac-only benchmark estimate | `TransferEstimateModel` (Task 3) |
| `remoteBackupQueue`, timer, scheduler flags, `hostTrustPrompt`, `hostTrustContinuation` and the SFTP methods | 28–34, 187–373 | Mac-only SFTP | `MacRemoteBackupController` (Task 2) |
| `canStartOperation`, `copyAndVerifyPreflightIsReady` | 45–51, 113–142 | a second readiness check | Merge into `SharedAppCoordinator.operationReadinessAssessment` (Task 6b) |
| `startOperation()` sync block, `makePhotographerReportContext()`, `configurePhotographerReportLifecycle()` | 66–111, 144–181 | Mac copy of the project start/finish lifecycle | `SharedAppCoordinator.startProjectOperation()` / `startCurrentMode()` (Task 8) |
| Pass-throughs: `isOperationInProgress`, `completionState`, `results`, `canPause`, `canResume`, `isPaused`, `operationState`, `verificationMode`, `cancelOperation`, `togglePause`, `switchMode`, `resetForNewOperation`, `saveVerificationMode` | 42–63, 183, 375–391 | forwarding only | Views call `SharedAppCoordinator` (Task 9) |
| `progressPercentage`, `currentFileName`, `formattedSpeed`, `formattedTimeRemaining` | 52–55 | forward to `ProgressViewModel` | Views read the progress model (Task 7) |
| `toggleCameraDetection`, `rescanForCameras` | 394–402 | Mac camera monitoring | `MacCameraAutoSourceController` (Task 6a) |
| `makePhotographerReportContext()` | 144–158 | **unused** (no callers) | Delete in Task 8 |

### 1.2 Every Combine sync it performs

Line numbers are unchanged since the first draft.

| # | Line | Subscription | What it does | Replacement |
|---|---|---|---|---|
| S1 | 481 | `fileSelection.$leftURL` → `shared.leftURL` | Mac → shared copy | Gone: the views write `shared.leftURL` (Task 6a) |
| S2 | 484 | `fileSelection.$rightURL` → `shared.rightURL` | Mac → shared copy | Gone (Task 6a) |
| S3 | 495 | `fileSelection.$sourceURL.dropFirst()` → camera label detect/clear, `photographerJobViewModel.sourceDidChange`, `updateTimeEstimate()` | fan-out on source change | Shared `$sourceURL.dropFirst()` sink calls `sourceDidChange` (Task 1) and the label model (Task 5); the estimate model observes shared (Task 6a) |
| S4 | 502 | `$destinationURLs.debounce(500 ms)` → `updateTimeEstimate()` | estimate refresh | `TransferEstimateModel` observes `shared.$destinationURLs` (Task 6a) |
| S5 | 507 | `$sourceFolderInfo` → `updateTimeEstimate()` | estimate refresh | `TransferEstimateModel` observes `shared.folderInfoService.$sourceFolderInfo` (Task 6a) |
| S6 | 511 | `$destinationURLs` → `saveLastDestinations()` | remember backups | `MacVolumeAccessModel` observes `shared.$destinationURLs` (Task 6a) |
| S7 | 516 | `cameraLabel.$destinationLabelSettings` → `onLabelChanged()` | persist the label and remember it for the camera | Label model persists and remembers on its own `didSet` (Task 5) |
| S8 | 520 | merge(source, dests, left, right) → `objectWillChange` | re-render relay | Gone: shared already publishes these (Task 6a) |
| S9 | 532 | merge(six progress fields) → `objectWillChange` | re-render relay | Gone: views observe the progress model directly (Task 7) |
| S10 | 547 | `BitMatchQueuedTransferSelected` notification → set `currentMode`, source, dests, label settings from shared | shared → Mac copy-back for queue replay | Gone: shared is already the owner. The only post is `SharedAppCoordinator.swift:373`; delete it with S10 (Task 8) |
| S11 | 556 | `shared.$progress.throttle(120 ms)` → `ProgressViewModel` setters | shared → Mac progress mapping | Moves into `SharedAppCoordinator` with the same throttle (Task 7) |
| S12 | 582 | `shared.$progress` (unthrottled) → `photographerJobViewModel.updateProgressStage` | project lifecycle | Already done in shared's `onProgress` when `activeProjectCardID != nil` (`SharedAppCoordinator.swift:497`) (Task 8) |
| S13 | 590 | `shared.$lastCompareStats` → `objectWillChange` | re-render relay | Replaced by one relay of `shared.objectWillChange` (Task 4), then gone (Task 9) |
| S14 | 597 | `shared.operationStatePublisher` → progress timer start/stop, reset `lastSharedBytesProcessed`, photographer `beginIngest` / `updateProgressStage(.verifying)` / `operationFailed` / `cancelIngest` | progress timer + project lifecycle | Timer → shared (Task 7); lifecycle → shared `startProjectOperation` + `updateProjectLifecycle` (Task 8) |
| S15 | 639 | `photographerJobViewModel.objectWillChange` → `objectWillChange` | nested-observable relay | `SharedAppCoordinator` forwards the job VM like `folderInfoService` (Task 8) |
| S16 | 643 | merge(shared `isOperationInProgress`, `operationStatePublisher`, `results`, `verificationMode`) → `objectWillChange` | re-render relay | Replaced by one relay of `shared.objectWillChange` (Task 4), then gone (Task 9) |
| S17 | 655 | `.cameraCardDetected` notification → auto-select source if prefs allow and readable | Mac auto-source | `MacCameraAutoSourceController` writes `shared.sourceURL` (Task 6a) |

The class also does some non-Combine syncing:

- **I1**, `startOperation()` lines 80–94: copies `currentMode`, camera label settings (with the photographer recipe applied), `settingsViewModel.prefs`, and source, destinations, left and right into shared just before every run. Tasks 4–6 remove each copy as shared becomes the owner; Task 5 turns the recipe overlay into a run-only setting so it is never saved as the user's label.
- **I2**, `ContentView.swift:88`: the History sheet's `onAppear` pushes `settingsViewModel.prefs` into `shared.reportSettings`. Task 4 removes it.
- **I3**, `store.whenAvailable` (line 468): starts the SFTP scheduler once Core Data loads. This moves in Task 2.

### 1.3 Mac views and types that use `AppCoordinator` or its view models

Legend: **P** progress, **F** file selection, **C** camera label, **S** settings, **J** photographer job VM, **R** remote/SFTP methods, **E** estimate, **H** host-trust prompt, **·** pass-through only.

| File | Type(s) | Uses | Notes |
|---|---|---|---|
| `BitMatch/App/ContentView.swift` | `ContentView` | F S J R H · | `@StateObject` creates `AppCoordinator()`; window-height math reads `F.sourceURL` and `F.destinationURLs.count`; results filter binds `S.showOnlyIssues`; host-trust alert; History sheet; keyboard/menu notifications call `switchMode` / `startOperation` / `cancelOperation` / `CompareFoldersView.startIfReady` |
| `BitMatch/Views/CopyAndVerify/CopyAndVerifyView.swift` | `CopyAndVerifyView` | F C S J R · | its own `readinessIssues`/`readinessWarnings`; pause/resume, start, remote queue callbacks |
| `BitMatch/Views/CopyAndVerify/TransferPlanView.swift` | `TransferPlanView`, `TransferOptionsView`, `MacTransferOptionsAdapter` | F C S J R E · | `timeEstimate`, `isCalculatingEstimate`, `C.detectedCamera`, `C.currentFingerprint`, `S.prefs.makeReport` |
| `BitMatch/Views/HorizontalFlowView.swift` | `HorizontalFlowView` | F P · | heaviest `F` user: drop handling, `addDestination`, `removeDestination`, `formattedAvailableSpace`, `detectDriveSpeed`, `sourceCameraLabel`, `sourceVideoFileCount`, `onReceive(F.$sourceURL / $destinationURLs)` |
| `BitMatch/Views/CompactTransfer/TransferQueueView.swift` | `TransferQueueView` | F P · | `P.destinationProgressFractions`, `formattedAverageDataRate`, `formattedFilesRemaining`, `coordinator.progressPercentage` (the P version) |
| `BitMatch/Views/ResultsTableView.swift` | `ResultsTableView` | F P · | `P.reusedFileCopies`, `shared.hasErrors` / `hasCriticalErrors` |
| `BitMatch/Views/CompareFoldersView.swift` | `CompareFoldersView` | F · | adapter over `CompareScreen`; `F.leftURL` / `rightURL` / folder info; bindings only |
| `BitMatch/Views/MasterReportView.swift` | `MasterReportView` | S | `S.prefs` for the report configuration; bindings only |
| `BitMatch/Views/PreferencesWindow.swift` | `PreferencesWindow`, `PreferencesWindowController`, `PreferencesWindow_Previews` | S J R · camera toggles | `S.prefs` bindings; `toggleCameraDetection`, `rescanForCameras`; `RemoteBackupDestinationManager`; the preview builds `AppCoordinator(photographerJobViewModel:)` |
| `BitMatch/Views/Photographer/PhotographerJobSetupView.swift` | `PhotographerJobSetupView` | F J | `F.sourceURL`, `F.sourceCameraLabel` (`onChange`) |
| `BitMatch/Views/Photographer/RemoteBackupDestinationView.swift` | `RemoteBackupDestinationView`, `RemoteBackupDestinationManager` | J R | `selectRemoteProfile`, `testRemoteProfile` |
| `BitMatch/Core/Services/DevModeManager.swift` | `DevModeManager` (DEBUG) | F P · | 7 methods take `AppCoordinator`; they set `F.sourceFolderInfo`, which shared cannot (folder info is scanned) |

Comments to update in Task 10: `FileSelectionViewModel.swift:143`, `CameraCardDetectionService.swift:255`, `CompareFoldersView.swift:5,10`, `TransferPlanView.swift:263`, `PreferencesWindow.swift:377`.

Tests:

- `BitMatchTests/AppCoordinatorBindingTests.swift`: 20 tests covering the syncs, the start gate, and the project lifecycle.
- `BitMatchTests/WorkflowSnapshotTests.swift`: builds both coordinators and drives the Mac one.
- `BitMatchTests/RemoteBackupQueueTests.swift:227`: the scheduler integration test.
- `BitMatchTests/FileSelectionFetchTests.swift`, `DestinationDismissalTests.swift`: `FileSelectionViewModel`.

### 1.4 Mac-only behaviour `AppCoordinator` adds, and where it goes

| Behaviour | Today | Goes to | Why Mac-only |
|---|---|---|---|
| **SFTP off-site backup**: queue restore on launch, run-due loop, backoff timer, pause/retry/cancel, profile test, SSH host-key trust prompt | `AppCoordinator` 187–373, 451–469 | New `BitMatch/Core/Services/MacRemoteBackupController.swift` | SFTP is the thesis's named Mac exception. `SFTPRemoteBackupProvider` and `OpenSSHHostTrustRequest` are in the Mac target. |
| **Benchmark time estimate** | `AppCoordinator` 405–426 + S3–S5; `DriveBenchmarkService` (Mac target) | New `BitMatch/Core/Services/TransferEstimateModel.swift` | `DriveBenchmarkService` is Mac-only and will be deleted in step 5 in favour of observed copy speed. The iPad path keeps `operationReadinessAssessment.estimatedDuration`. |
| **Auto-select detected camera card** | S17, `toggleCameraDetection`, `rescanForCameras`, `CameraCardDetectionService` | New `BitMatch/Core/Services/MacCameraAutoSourceController.swift` | iOS cannot watch mounted volumes. The preferences (`enableAutoCameraDetection`, `autoPopulateSource`) stay in the shared `ReportPrefs`. |
| **Volume access, bookmarks, recents, drive speed, last destinations, backup-drive discovery** | `FileSelectionViewModel` | Rename what remains to `MacVolumeAccessModel` | NSOpenPanel, `/Volumes` bookmarks and `VolumeMonitorService` are macOS APIs |
| **Window sizing** | `ContentView` (`idealWindowHeight`, `updateWindowSize`, `restoreWindowFrame`), `BitMatchApp.setupWindow`, `WindowPresentationPolicy`. `AppCoordinator` only supplies `currentMode` and `F.destinationURLs.count` / `F.sourceURL`. | Stays in `ContentView`, reading `shared.currentMode`, `shared.destinationURLs.count` and `shared.sourceURL` | Resizing an `NSWindow` is Mac-only. |

---

## 2. Behaviour differences to settle, not paper over

1. **Two job view models on Mac.** `SharedAppCoordinator.init` always creates its own `PhotographerJobViewModel` (UserDefaults store, `UnavailableRemoteProjectCoordinator`). On Mac that instance is never shown, but shared's `$sourceURL` sink still calls `sourceDidChange` on it. Fix: inject the Mac instance (Task 1).
2. **Initial `sourceDidChange(nil)`.** Shared's `$sourceURL` sink (`SharedAppCoordinator.swift:186-196`) has no `dropFirst()`, and calls `sourceDidChange` only after awaiting camera detection. The Mac comment at `AppCoordinator.swift:488` explains that without `dropFirst()` a card prepared from the persisted store is invalidated at launch. Task 1 moves the call into its own synchronous `dropFirst()` sink, with a test.
3. **Readiness check (decided).** Shared enforces the stricter union on every platform: block while the source is still being analysed, and block when a destination's free space is not more than the source size plus 1 GB (`SafetyValidator.requiredHeadroomBytes`, the runtime rule, checked for every destination whose capacity is readable). Keep the 70% warning. An analysing source makes the assessment not ready without adding an issue string, so iPad keeps showing "Analyzing" rather than "Blocked".
4. **Camera auto-label (decided).** The memory-aware Mac path becomes the one shared path (Task 5). iPad/iPhone labels become smarter and are remembered per card.
5. **Persistence of report and label settings (decided).** Shared loads and saves `ReportPrefs` (`BitMatch_ReportPrefs_JSON`, `BitMatch_MakeReportEnabled`) and `CameraLabelSettings` (`destLabelSettings`) with the Mac keys, so Mac users keep their settings and iPad/iPhone remember them. Queue replay uses the record's settings for that run only and restores the user's afterwards (UI plan §8 item 8).
6. **Folder info.** Mac scans the source itself (`FileSelectionViewModel.scanFolderInfo`), and shared scans again once `startOperation` copies `sourceURL` in. Use `FolderInfoService` only. `sourceVideoFileCount` becomes `EnhancedFolderInfo.videoFileCount` (from the full scan's extension breakdown); `sourceCameraLabel` becomes the label model's `detectedCameraName`; `sourceIsWriteProtected` has no reader and is dropped.
7. **Progress presentation.** Keep the richer Mac model (interpolation, EMA speed, rolling ETA, per-destination fractions, reused copies), moved to `Shared/` and fed by the coordinator. Moving iPad onto it belongs to thesis step 4.

---

## 3. Steps

Each task leaves both apps compiling. While a piece moves, `AppCoordinator` keeps a forwarding property **with the name `SharedAppCoordinator` uses** (`reportSettings`, `cameraLabelSettings`, `sourceURL`, …), and the Mac views are rewritten to that name in the same commit. Task 9 then only changes the views' coordinator type and hands them the companions. Task 10 deletes the file.

### Task 0: Pin current behaviour with tests

**Files:** `BitMatchTests/SharedCoordinatorTestSupport.swift`, `BitMatchTests/SharedCoordinatorMacParityTests.swift` (new)

- [ ] Port the behaviours `AppCoordinatorBindingTests` pins to tests against `SharedAppCoordinator` with real temporary folders, an `InMemoryPhotographerJobStore` and a recording file-operations stub: a two-copy job with one backup is refused; a changed source is refused; cancelling cancels the prepared card; a failed start ends the card in issues; an unverified finish ends the card in issues; compare runs never touch a prepared card.
- [ ] Mark what shared does not do yet with `withKnownIssue` and the task that fixes it: start while the source is analysing (Task 6b); the project recipe reaching the run's settings (Task 8). **Never skip a test.**
- [ ] The engine-level verdict parity already exists (`PlatformVerdictParityTests`); do not duplicate it.

### Task 1: One job view model on Mac

**Files:** `Shared/Core/Services/SharedAppCoordinator.swift`, `BitMatch/App/AppCoordinator.swift`, tests

- [ ] Add `photographerJobViewModel: PhotographerJobViewModel? = nil` to `SharedAppCoordinator.init`, used instead of building one from `projectStore` when present. iPad call sites are unchanged.
- [ ] Call `sourceDidChange` from its own `$sourceURL.dropFirst()` sink, synchronously. Test: a prepared card survives coordinator init.
- [ ] `AppCoordinator.init` builds the Core Data job VM first and passes it in; `AppCoordinator.photographerJobViewModel` becomes a forward. When a test passes `sharedCoordinator:`, the job VM is that coordinator's. `WorkflowSnapshotTests` passes its VM to `SharedAppCoordinator` instead.

### Task 2: Extract SFTP into `MacRemoteBackupController`

**Files:** `BitMatch/Core/Services/MacRemoteBackupController.swift` (new), `AppCoordinator.swift`, `BitMatchTests/RemoteBackupQueueTests.swift`

- [ ] Move `HostTrustPrompt`, the queue, timer, scheduler flags, host-trust continuation and every SFTP method into the controller, bodies unchanged. It takes the job VM, a `results` closure and an optional queue.
- [ ] `makeDefault(store:jobViewModel:results:startScheduler:)` builds the SFTP queue (its host-key closure calls back into the controller) and arms `store.whenAvailable`.
- [ ] `AppCoordinator` holds `let remoteBackups` and one-line forwards for the old names, and relays the controller's changes so the host-key alert still appears.
- [ ] Retarget `RemoteBackupQueueTests.swift:227` to the controller.

### Task 3: Extract the benchmark estimate into `TransferEstimateModel`

**Files:** `BitMatch/Core/Services/TransferEstimateModel.swift` (new), `AppCoordinator.swift`, tests

- [ ] `@MainActor final class TransferEstimateModel: ObservableObject` with `estimate`, `isCalculating` and `update(source:destinations:totalBytes:mode:)`, with an injectable estimator (default `DriveBenchmarkService`) and a generation token so a slow, stale benchmark cannot overwrite a newer one. Today it can. Test it.
- [ ] `AppCoordinator` owns one, calls `update` from S3–S5, forwards `timeEstimate` / `isCalculatingEstimate`, and now also refreshes when the verification mode changes (today it does not).
- [ ] This is the only `DriveBenchmarkService` caller left, so deleting the benchmark in step 5 touches one file.

### Task 4a: Delete the ignored report format checkboxes

**Files:** `Shared/Core/Models/TransferModels.swift`, `Shared/Core/Models/TransferPlanPresentation.swift`, `BitMatch/Views/PreferencesWindow.swift`, `BitMatchTests/TransferPlanPresentationTests.swift`

- [ ] Remove "Generate PDF" and "Generate CSV" from Preferences and the two `ReportPrefs` fields. Old saved JSON still decodes (extra keys are ignored).
- [ ] The option summary says what the writer produces: "Reports: PDF, CSV" on macOS and "Reports: CSV" on iOS.

### Task 4: Report settings live in `SharedAppCoordinator`

**Files:** `Shared/Core/Services/ReportPrefsStore.swift` (new), `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `ContentView.swift`, `CopyAndVerifyView.swift`, `TransferPlanView.swift`, `MasterReportView.swift`, `PreferencesWindow.swift`; delete `BitMatch/Core/ViewModels/SettingsViewModel.swift`

- [ ] `ReportPrefsStore` loads and saves with the same keys. `SharedAppCoordinator` takes a `preferences: UserDefaults?` (tests default to a throwaway suite, like the journal), loads `reportSettings` at init and saves on `didSet`, except while a queued transfer replays; replay restores the user's settings when it ends.
- [ ] Views bind `coordinator.reportSettings` (an `AppCoordinator` forward until Task 9). `showOnlyIssues` becomes `@State` in `ContentView`.
- [ ] Delete I1's `reportSettings` copy and I2's `onAppear` push. Replace S13 and S16 with one relay of `sharedCoordinator.objectWillChange` (still on the next run-loop turn, as today).
- [ ] Delete `SettingsViewModel` (its notification and toggle helpers have no callers).
- [ ] Check on iPad and iPhone simulators that report toggles survive a relaunch.

### Task 5: Camera label lives in `SharedAppCoordinator`

**Files:** `git mv BitMatch/Core/ViewModels/CameraLabelViewModel.swift Shared/Core/ViewModels/CameraLabelModel.swift`, `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `TransferPlanView.swift`, tests

- [ ] `CameraLabelModel` owns `settings` (same `destLabelSettings` key, saved and remembered for the card on `didSet`, which replaces S7), `detectedCamera`, `currentFingerprint`, and `detectedCameraName` (the cleaned name `HorizontalFlowView` shows). Clearing the source cancels any in-flight detection.
- [ ] `SharedAppCoordinator.cameraLabelSettings` forwards to the model, and the coordinator forwards the model's changes. The `$sourceURL.dropFirst()` sink runs `detectCameraWithMemory` or `clearCameraLabel` (decision §2.4). The iPad `detectedCamera: CameraCard?` detection stays, but no longer writes the label and no longer delays the folder scan.
- [ ] `projectRunCameraSettings` is a run-only override the executor uses instead of `cameraLabelSettings`; I1's recipe overlay writes it, so the recipe never becomes the saved label. Queue replay restores the user's label when it ends.
- [ ] Remove the label part of S3, I1's label copy and S10's label copy-back.
- [ ] Check on iPad and iPhone that the label is suggested and remembered per card.

### Task 6a: Selection lives in `SharedAppCoordinator`; Mac volume parts split out

**Files:** `SharedAppCoordinator.swift`, `FolderInfoService.swift`, `SharedModels.swift`, `git mv BitMatch/Core/ViewModels/FileSelectionViewModel.swift BitMatch/Core/ViewModels/MacVolumeAccessModel.swift`, `BitMatch/Core/Services/MacCameraAutoSourceController.swift` (new), `TransferEstimateModel.swift`, `AppCoordinator.swift`, `ContentView.swift`, `HorizontalFlowView.swift`, `CopyAndVerifyView.swift`, `TransferPlanView.swift`, `TransferQueueView.swift`, `ResultsTableView.swift`, `CompareFoldersView.swift` (bindings only), `PhotographerJobSetupView.swift`, `DevModeManager.swift`, tests

- [ ] Views read `coordinator.sourceURL` / `destinationURLs` / `leftURL` / `rightURL` / `sourceFolderInfo` (`.asFolderInfo` where a `FolderInfo` is expected) / `isAnalysingSource` / `isAnalysing(left:)`. `FolderInfoService` answers "still analysing" as *not yet scanned for this URL, or scanning*, so the gap before its task runs counts as analysing.
- [ ] `MacVolumeAccessModel(shared:)` keeps the volume monitor, bookmarks, recents, last destinations (S6), backup-drive discovery with dismissals, `formattedAvailableSpace`, `detectDriveSpeed` and `DriveSpeed`. Selection changes go through shared. `SharedAppCoordinator.addDestination(_:)` dedups by resolved path and backs the iOS picker too.
- [ ] `MacCameraAutoSourceController(shared:)` owns `CameraCardDetectionService`, S17, `toggleCameraDetection` and `rescanForCameras`, using `AutomaticSourceSelectionPolicy`.
- [ ] `TransferEstimateModel.bind(to:)` observes shared (S3–S5 plus verification mode).
- [ ] Delete S1, S2, S8, I1's selection copies and S10's selection copy-back.
- [ ] `FileSelectionFetchTests` becomes `FolderInfoService` tests; `DestinationDismissalTests` drives `MacVolumeAccessModel` over a shared coordinator.
- [ ] On Mac: drag-and-drop, auto-detected card selection, ejecting a backup, relaunch restoring last destinations.

### Task 6b: One readiness rule

**Files:** `SharedAppCoordinator.swift`, `SafetyValidator.swift`, `AppCoordinator.swift`, `CopyAndVerifyView.swift` (Mac), tests

- [ ] `OperationReadinessAssessment.assess(...)` is a pure function with injected free space (§2.3). `operationReadinessAssessment` calls it; it adds `blockingIssues` (real findings, without the two "not chosen yet" strings) and `isAnalysing`.
- [ ] `SafetyValidator.requiredHeadroomBytes` is the one 1 GB constant, used by the runtime and the preflight.
- [ ] `AppCoordinator.canStartOperation` and its start guard use shared; `copyAndVerifyPreflightIsReady` is deleted. The Mac `CopyAndVerifyView` passes shared's `blockingIssues`/`warnings` to `TransferPlanPresentation`, so the Mac and iOS messages are the same strings. This is the rule UI plan step 4.5's `TransferReadiness` should wrap.
- [ ] Tests: blocked while analysing; blocked at exactly source + 1 GB free even with no destination folder info; ready just above. Remove Task 0's `withKnownIssue` for the analysing gate.

### Task 7: Progress presentation lives in `Shared/`

**Files:** `git mv BitMatch/Core/ViewModels/ProgressViewModel.swift Shared/Core/ViewModels/ProgressPresentationModel.swift`, `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `HorizontalFlowView.swift`, `TransferQueueView.swift`, `ResultsTableView.swift`, `DevModeManager.swift`, tests

- [ ] `SharedAppCoordinator` owns `let progressPresentation`. It runs S11's mapping (120 ms throttle, private byte-delta state) and S14's timer handling, and `resetForNewOperation()` resets it. The per-destination guard uses the running transfer's destination count.
- [ ] Views `@ObservedObject` the model directly and use its `displayProgress`, rolling rate and ETA, not shared's `progressPercentage` / `formattedSpeed` / `formattedTimeRemaining`. Drop S9 and the four forwards.
- [ ] iPad: no change (adopting the model is step 4).
- [ ] On Mac, check that the speed, ETA and per-destination bars move during a real copy.

### Task 8: One project lifecycle and one mode

**Files:** `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `BitMatchTests/AppCoordinatorBindingTests.swift` → `SharedCoordinatorMacParityTests.swift`

- [ ] `startProjectOperation()` refuses while anything runs, applies the job's recipe through `PhotographerDestinationResolver` to `projectRunCameraSettings` (iPad/iPhone project cards ran without it until now), and ends a card that never reached a terminal state in issues.
- [ ] `startCurrentMode()` is the one Start: prepared card → `startProjectOperation()`, otherwise `startOperation()` when `canStartOperation`; Compare → `compareFolders()`.
- [ ] `SharedAppCoordinator` forwards the job VM's changes (replacing S15).
- [ ] Delete from `AppCoordinator`: `configurePhotographerReportLifecycle`, `makePhotographerReportContext`, S12, S14's lifecycle half, S15, `currentMode` (a forward to shared now), S10 and the `BitMatchQueuedTransferSelected` post. `switchMode` uses shared's lock.
- [ ] Move the remaining lifecycle tests into the parity suite and remove Task 0's recipe `withKnownIssue`.
- [ ] On Mac: one ordinary copy, one prepared project card, one cancelled card, one queued-transfer replay.

### Task 9: Retarget Mac views to `SharedAppCoordinator`

- [ ] `MacAppEnvironment` (new, `BitMatch/App/`) builds the coordinator and the four companions once (`make()` wires the Core Data store, job VM and SFTP queue). `ContentView` holds it as its only `@StateObject` and renders `MacMainView` (today's `ContentView` body) with each object observed directly. `MacRemoteBackupController`, `MacVolumeAccessModel` and `TransferEstimateModel` are environment objects; `PreferencesWindowController` injects them into its own hosting view.
- [ ] Every view changes `AppCoordinator` to `SharedAppCoordinator`. `coordinator.sharedCoordinator.x` becomes `coordinator.x`. Views that read the job VM, label model or progress model observe them directly.
- [ ] `DevModeManager`: the Mac overloads take `SharedAppCoordinator`; fake folder info is no longer injected (the scanner reports what is on disk).
- [ ] `WorkflowSnapshotTests` builds a `MacAppEnvironment` for testing.
- [ ] After each view: build the Mac scheme; resize the window from compact to wide; check the view with keyboard only and without hover.

### Task 10: Delete `AppCoordinator`

- [ ] Delete `BitMatch/App/AppCoordinator.swift` and what is left of `AppCoordinatorBindingTests` (its relay tests test the relay being deleted).
- [ ] Update the comments listed in §1.3, `ARCHITECTURE.md`, `docs/THESIS.md` (step 3 done, the "676 lines" finding) and `CHANGELOG.md`.
- [ ] `rg -n '\bAppCoordinator\b' --glob '!**/SharedAppCoordinator*'` returns only historical plan/spec docs.
- [ ] Build `BitMatch` and `BitMatch-iPad` (Debug and Release); run `BitMatchTests` and `BitMatch-iPadTests`; run `./test.sh`.
- [ ] Manual pass on a Mac with a real card and two backups: copy, verify, report, ASC MHL, history, compare, master report, SFTP queue with host-key prompt, preferences round-trip, relaunch. Record whether this was simulator/build validation or a physical-device run.

---

## 4. Risks

- **Test-injection seams.** `AppCoordinator.init` has six injection points, which tests rely on. Tasks 1, 2, 4 and 6a add the equivalents (`photographerJobViewModel:` and `preferences:` on `SharedAppCoordinator`, and the companions' own initializers).
- **Nested observables.** SwiftUI does not re-render when a nested `ObservableObject` changes. `SharedAppCoordinator` forwards `folderInfoService`, `transferJournal`, `stateService`, and after this plan the label model and the job VM. The progress model is deliberately **not** forwarded (it changes every 250 ms); views read it through their own `@ObservedObject`. A missed one fails silently with stale values, which breaks promise 2, so check every retargeted view during a live run.
- **Environment objects.** A missing `environmentObject` crashes at runtime, not at build time. The two hosting roots are `ContentView` and `PreferencesWindowController`.
- **Throttling.** S11's 120 ms throttle moves into the coordinator in Task 7; keep it.
- **iPad behaviour changes** (§2.3, 2.4, 2.5) are deliberate but visible. Call them out in the changelog and check them on iPhone and iPad simulators, not only the Mac.
- **Size.** Expect about −680 lines from `AppCoordinator`, about −120 from `SettingsViewModel`, and about −300 of duplicate scanning and readiness code in the file-selection VM. The companions add about 450, mostly moved SFTP code.
