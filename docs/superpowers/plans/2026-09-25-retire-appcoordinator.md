# Retire AppCoordinator Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans (or subagent-driven-development) to carry this out task by task. Steps use checkbox (`- [ ]`) syntax. Each task must build the `BitMatch` (macOS) and `BitMatch-iPad` schemes and pass `BitMatchTests` before it is committed.

**Goal:** Delete `BitMatch/App/AppCoordinator.swift`. Mac views bind to `SharedAppCoordinator` directly, as iPad and iPhone already do. This is step 3 of the plan in [docs/THESIS.md](../../THESIS.md) and serves promise 5, "One app everywhere".

**Status:** Plan only. It was written in an environment with no Xcode, so nothing here has been compiled or run. Line numbers refer to `main` at `9ff3f85`.

**Architecture:** Today macOS runs two coordinators. `SharedAppCoordinator` owns the engine, operation state, results, journal and queue. `AppCoordinator` wraps it and owns five Mac-only view models (`ProgressViewModel`, `FileSelectionViewModel`, `CameraLabelViewModel`, `SettingsViewModel`, and its own `PhotographerJobViewModel`) plus `CameraCardDetectionService`. It keeps them in step with 17 Combine subscriptions and a block of imperative copies in `startOperation()`. After this plan, `SharedAppCoordinator` is the only state owner on every platform. Mac-only abilities (SFTP, the drive benchmark, volume monitoring and auto-selecting a detected card, Mac window sizing) move into small Mac-only companions that read from and write to `SharedAppCoordinator`. None of them keeps its own copy of shared state.

**Out of scope:** merging the Mac and iPad view files (thesis step 4), collapsing `operationState` and `OperationStateService` (thesis step 2), Core Data vs. JSON job storage, and Swift 6. This plan should not make any of those harder.

---

## 1. Inventory

### 1.1 What `AppCoordinator` owns

| Member | Lines | Kind | Destination |
|---|---|---|---|
| `sharedCoordinator` | 17 | the real core | Becomes the only coordinator |
| `progressViewModel: ProgressViewModel` | 22 | mirrored VM #1 | `Shared/`, owned by `SharedAppCoordinator` (Task 7) |
| `fileSelectionViewModel: FileSelectionViewModel` | 23 | mirrored VM #2 | Selection URLs → `SharedAppCoordinator`; Mac volume/bookmark/recents parts → `MacVolumeAccessModel` (Task 6) |
| `cameraLabelViewModel: CameraLabelViewModel` | 24 | mirrored VM #3 | `Shared/`, owned by `SharedAppCoordinator` (Task 5) |
| `settingsViewModel: SettingsViewModel` | 25 | mirrored VM #4 | `SharedAppCoordinator.reportSettings` + `ReportPrefsStore` (Task 4) |
| `photographerJobViewModel` (Core Data store, SFTP-capable) | 27 | mirrored VM #5 | Injected into `SharedAppCoordinator` (Task 1) |
| `cameraDetectionService: CameraCardDetectionService` | 26 | Mac service | `MacCameraAutoSourceController` (Task 6) |
| `currentMode` | 37 | duplicate of `sharedCoordinator.currentMode`, copied only at start | Delete; use shared `currentMode` / `switchMode` (Task 8) |
| `timeEstimate`, `isCalculatingEstimate`, `updateTimeEstimate()` | 38–39, 405–426 | Mac-only benchmark estimate | `TransferEstimateModel` (Task 3) |
| `remoteBackupQueue`, timer, scheduler flags, `hostTrustPrompt`, `hostTrustContinuation` and the SFTP methods | 28–34, 187–373 | Mac-only SFTP | `MacRemoteBackupController` (Task 2) |
| `canStartOperation`, `copyAndVerifyPreflightIsReady` | 45–51, 113–142 | a second readiness check | Merge into `SharedAppCoordinator.operationReadinessAssessment` (Task 6) |
| `startOperation()` sync block, `makePhotographerReportContext()`, `configurePhotographerReportLifecycle()` | 66–111, 144–181 | Mac copy of the project start/finish lifecycle | `SharedAppCoordinator.startProjectOperation()` (Task 8) |
| Pass-throughs: `isOperationInProgress`, `completionState`, `results`, `canPause`, `canResume`, `isPaused`, `operationState`, `verificationMode`, `cancelOperation`, `togglePause`, `switchMode`, `resetForNewOperation`, `saveVerificationMode` | 42–63, 183, 375–391 | forwarding only | Views call `SharedAppCoordinator` (Task 9) |
| `progressPercentage`, `currentFileName`, `formattedSpeed`, `formattedTimeRemaining` | 52–55 | forward to `ProgressViewModel` | Views read the progress model (Task 7) |
| `toggleCameraDetection`, `rescanForCameras` | 394–402 | Mac camera monitoring | `MacCameraAutoSourceController` (Task 6) |
| `makePhotographerReportContext()` | 144–158 | **unused** (no callers) | Delete in Task 8 |

### 1.2 Every Combine sync it performs

| # | Line | Subscription | What it does | Replacement |
|---|---|---|---|---|
| S1 | 481 | `fileSelection.$leftURL` → `shared.leftURL` | Mac → shared copy | Gone: the views write `shared.leftURL` (Task 6) |
| S2 | 484 | `fileSelection.$rightURL` → `shared.rightURL` | Mac → shared copy | Gone (Task 6) |
| S3 | 495 | `fileSelection.$sourceURL.dropFirst()` → camera label detect/clear, `photographerJobViewModel.sourceDidChange`, `updateTimeEstimate()` | fan-out on source change | Shared `$sourceURL` sink (already calls `sourceDidChange`, **needs `dropFirst()`**, Task 1) + label model (Task 5) + estimate model (Task 3) |
| S4 | 502 | `$destinationURLs.debounce(500 ms)` → `updateTimeEstimate()` | estimate refresh | `TransferEstimateModel` observes `shared.$destinationURLs` (Tasks 3, 6) |
| S5 | 507 | `$sourceFolderInfo` → `updateTimeEstimate()` | estimate refresh | `TransferEstimateModel` observes `shared.folderInfoService` (Tasks 3, 6) |
| S6 | 511 | `$destinationURLs` → `saveLastDestinations()` | remember backups | `MacVolumeAccessModel` observes `shared.$destinationURLs` (Task 6) |
| S7 | 516 | `cameraLabel.$destinationLabelSettings` → `onLabelChanged()` | persist the label and remember it for the camera | Label model persists on its own `didSet` (Task 5) |
| S8 | 520 | merge(source, dests, left, right) → `objectWillChange` | re-render relay | Gone: these become `@Published` on shared (Task 6) |
| S9 | 532 | merge(six progress fields) → `objectWillChange` | re-render relay | Gone: views observe the progress model directly (Task 7) |
| S10 | 547 | `BitMatchQueuedTransferSelected` notification → set `currentMode`, source, dests, label settings from shared | shared → Mac copy-back for queue replay | Gone: shared is already the owner. Delete the notification post at `SharedAppCoordinator.swift:344` if nothing else listens (Task 8) |
| S11 | 556 | `shared.$progress.throttle(120 ms)` → `ProgressViewModel` setters (totals, per-destination, current file, reused copies, byte delta via `lastSharedBytesProcessed`, message) | shared → Mac progress mapping | The progress model is fed by `SharedAppCoordinator` itself (Task 7) |
| S12 | 582 | `shared.$progress` (unthrottled) → `photographerJobViewModel.updateProgressStage` | project lifecycle | Already done in shared's `onProgress` when `activeProjectCardID != nil` (`SharedAppCoordinator.swift:466`) (Task 8) |
| S13 | 590 | `shared.$lastCompareStats` → `objectWillChange` | re-render relay | Gone: views observe shared (Task 9) |
| S14 | 597 | `shared.$operationState` → progress timer start/stop, reset `lastSharedBytesProcessed`, photographer `beginIngest` / `updateProgressStage(.verifying)` / `operationFailed` / `cancelIngest` | progress timer + project lifecycle | Timer handling → progress model (Task 7); lifecycle → shared `startProjectOperation` + `updateProjectLifecycle` (Task 8) |
| S15 | 639 | `photographerJobViewModel.objectWillChange` → `objectWillChange` | nested-observable relay | Views `@ObservedObject` the job view model, as iPad does (Task 9) |
| S16 | 643 | merge(shared `isOperationInProgress`, `operationState`, `results`, `verificationMode`) → `objectWillChange` | re-render relay | Gone: views observe shared (Task 9) |
| S17 | 655 | `.cameraCardDetected` notification → auto-select source if prefs allow and readable | Mac auto-source | `MacCameraAutoSourceController` writes `shared.sourceURL` (Task 6) |

The class also does some non-Combine syncing:

- **I1**, `startOperation()` lines 80–94: copies `currentMode`, camera label settings (with the photographer recipe applied), `settingsViewModel.prefs`, and source, destinations, left and right into shared just before every run. After Task 6 this is unnecessary because shared already holds the values.
- **I2**, `ContentView.swift:83`: the History sheet's `onAppear` pushes `settingsViewModel.prefs` into `shared.reportSettings`. Task 4 removes it.
- **I3**, `store.whenAvailable` (line 468): starts the SFTP scheduler once Core Data loads. This moves in Task 2.

### 1.3 Mac views and types that use `AppCoordinator` or its view models

Legend: **P** progress, **F** file selection, **C** camera label, **S** settings, **J** photographer job VM, **R** remote/SFTP methods, **E** estimate, **H** host-trust prompt, **·** pass-through only.

| File | Type(s) | Uses | Notes |
|---|---|---|---|
| `BitMatch/App/ContentView.swift` | `ContentView` | F S J R H · | `@StateObject` creates `AppCoordinator()`; window-height math reads `F.sourceURL` and `F.destinationURLs.count`; results filter binds `S.showOnlyIssues`; host-trust alert; keyboard/menu notifications call `switchMode` / `startOperation` / `cancelOperation` |
| `BitMatch/Views/CopyAndVerify/CopyAndVerifyView.swift` | `CopyAndVerifyView` | F C S J R · | pause/resume, start, remote queue callbacks |
| `BitMatch/Views/CopyAndVerify/TransferPlanView.swift` | `TransferPlanView` (l.5), `TransferOptionsView` (l.265) | F C S J R E · | reads `shared.generateASCMHL`, `timeEstimate`, `isCalculatingEstimate`, `C.detectedCamera`, `C.currentFingerprint` |
| `BitMatch/Views/HorizontalFlowView.swift` | `HorizontalFlowView` | F P · | heaviest `F` user: drop handling, `addDestination`, `removeDestination`, `formattedAvailableSpace`, `detectDriveSpeed`, `sourceCameraLabel`, `sourceVideoFileCount`, `onReceive(F.$sourceURL / $destinationURLs)` |
| `BitMatch/Views/CompactTransfer/TransferQueueView.swift` | `TransferQueueView` | F P · | `P.destinationProgressFractions`, `formattedAverageDataRate`, `formattedFilesRemaining` |
| `BitMatch/Views/ResultsTableView.swift` | `ResultsTableView` | F P · | `P.reusedFileCopies`, `shared.hasErrors` / `hasCriticalErrors` |
| `BitMatch/Views/CompareFoldersView.swift` | `CompareFoldersView` | F P S · | `F.leftURL` / `rightURL`, `shared.lastCompareStats`, `canStartOperation` |
| `BitMatch/Views/MasterReportView.swift` | `MasterReportView` | S | `S.prefs.production`, `.clientName`, `.company`, `.notes` |
| `BitMatch/Views/PreferencesWindow.swift` | `PreferencesWindow`, `PreferencesWindowController`, `PreferencesWindow_Previews` | S J · camera toggles | 19 uses of `S.prefs`; `toggleCameraDetection`, `rescanForCameras`; the preview builds `AppCoordinator(photographerJobViewModel:)` |
| `BitMatch/Views/Photographer/PhotographerJobSetupView.swift` | `PhotographerJobSetupView` | F J | `F.sourceURL`, `F.sourceCameraLabel` (`onChange`) |
| `BitMatch/Views/Photographer/RemoteBackupDestinationView.swift` | `RemoteBackupDestinationView`, `RemoteBackupDestinationManager` | J R | `selectRemoteProfile`, `testRemoteProfile` |
| `BitMatch/Core/Services/DevModeManager.swift` | `DevModeManager` (DEBUG) | F P · | 7 methods take `AppCoordinator` (l.112, 234, 248, 344, 372, 394, 414); `SharedAppCoordinator` overloads already exist from l.296 |

These files don't reference `AppCoordinator` but are affected: `PhotographerSessionDashboard` (takes `PhotographerJobViewModel`, no change needed); `FileSelectionViewModel.swift:143` and `CameraCardDetectionService.swift:255` (their comments mention `AppCoordinator` and need updating).

Tests:

- `BitMatchTests/AppCoordinatorBindingTests.swift`: 20 tests covering the syncs, the start gate, and the project lifecycle.
- `BitMatchTests/WorkflowSnapshotTests.swift`: builds both coordinators and drives the Mac one.
- `BitMatchTests/RemoteBackupQueueTests.swift:227`: the scheduler integration test.

### 1.4 Mac-only behaviour `AppCoordinator` adds, and where it goes

| Behaviour | Today | Goes to | Why Mac-only |
|---|---|---|---|
| **SFTP off-site backup**: queue restore on launch, run-due loop, backoff timer, pause/retry/cancel, profile test, SSH host-key trust prompt | `AppCoordinator` 187–373, 451–469 | New `BitMatch/Core/Services/MacRemoteBackupController.swift` (`@MainActor ObservableObject`), owned by the Mac `ContentView` | SFTP is the thesis's named Mac exception. `SFTPRemoteBackupProvider` and `OpenSSHHostTrustRequest` are in the Mac target. |
| **Benchmark time estimate** | `AppCoordinator` 405–426 + S3–S5; `DriveBenchmarkService` (Mac target) | New `BitMatch/Core/Services/TransferEstimateModel.swift`, observing shared inputs | `DriveBenchmarkService` is Mac-target code today. Whether it can run on iOS should be a separate, explicit decision. The iPad path keeps `operationReadinessAssessment.estimatedDuration`. |
| **Auto-select detected camera card** | `setupCameraDetection` (S17), `toggleCameraDetection`, `rescanForCameras`, `CameraCardDetectionService` | New `BitMatch/Core/Services/MacCameraAutoSourceController.swift` | iOS cannot watch mounted volumes. The preference stays in `ReportPrefs` (`enableAutoCameraDetection`, `autoPopulateSource`), which is shared. |
| **Volume access, bookmarks, recents, drive speed, last destinations** | `FileSelectionViewModel` | Rename what remains to `MacVolumeAccessModel` | NSOpenPanel, `/Volumes` bookmarks and `VolumeMonitorService` are macOS APIs |
| **Window sizing** | Not in `AppCoordinator`. It is in `ContentView` (`idealWindowHeight`, `updateWindowSize`, `restoreWindowFrame`), `BitMatchApp.setupWindow`, and `WindowPresentationPolicy`. `AppCoordinator` only supplies `currentMode` and `F.destinationURLs.count` / `F.sourceURL`. | Stays in `ContentView`, reading `shared.currentMode`, `shared.destinationURLs.count` and `shared.sourceURL` | Resizing an `NSWindow` is Mac-only. Nothing moves; only the three inputs change (Task 9). |

---

## 2. Behaviour differences to settle, not paper over

The Mac and shared paths differ in these places. Each task below says which one it resolves. Where a choice is needed the plan recommends one; confirm it with Mike before merging if it changes what iPad/iPhone users see.

1. **Two job view models on Mac.** `SharedAppCoordinator.init` always creates its own `PhotographerJobViewModel` backed by `UserDefaultsPhotographerJobStore` with `UnavailableRemoteProjectCoordinator`. On Mac that instance is never shown, but shared's `$sourceURL` sink still calls `sourceDidChange` on it. Fix: inject the Mac instance (Task 1).
2. **Initial `sourceDidChange(nil)`.** Shared's `$sourceURL` sink (`SharedAppCoordinator.swift:160`) has no `dropFirst()`. The Mac comment at `AppCoordinator.swift:488` explains that without it, a card prepared from the persisted store is invalidated at launch. That is harmless on iPad today but not once the Core Data VM is injected. Add `dropFirst()` in Task 1, and add a test.
3. **Readiness check.** Mac `copyAndVerifyPreflightIsReady` also blocks while `isFetchingSourceInfo`, and requires `available ≥ sourceSize + 100 MB` on every destination. Shared `operationReadinessAssessment` blocks at `sourceSize / available > 0.9` and warns above 0.7, and only for destinations whose folder info has loaded. **Recommendation:** make shared enforce the stricter union. Block while the source is analysing (iPad passes `isAnalyzing` into `TransferPlanPresentation` and gates on `plan.canStart` at view level; the engine-side rule should not depend on a view), and block when free space is below `sourceSize + 100 MB`. Keep the 0.7 warning. This serves promise 1, and iPad users get the same verdict as Mac users.
4. **Camera auto-label.** Shared `detectCameraFromSource` sets `cameraLabelSettings.label = camera.name` when the label is empty and confidence is above 0.8. Mac `CameraLabelViewModel.detectCameraWithMemory` uses `CameraMemoryService` fingerprints, remembered labels and `CameraNamingService` suggestions. Both depend only on `Shared/` services. **Recommendation:** make the memory-aware path the one shared path (Task 5). This is an iPad/iPhone behaviour change: the label becomes smarter and is remembered per card, so check it on both.
5. **Persistence of report and label settings.** Mac persists `ReportPrefs` (`BitMatch_ReportPrefs_JSON`, `BitMatch_MakeReportEnabled`) and `CameraLabelSettings` (`destLabelSettings`) in `UserDefaults`. iPad/iPhone persist neither, so they reset every launch. Moving persistence into shared changes iPad to remember them. **Recommendation:** accept that change. It is what "behavior does not [adapt]" means. Keys stay the same, so Mac users keep their settings.
6. **Folder info.** Mac scans the source itself (`FileSelectionViewModel.scanFolderInfo` → `FolderInfo`, plus `sourceVideoFileCount`, `sourceCameraLabel`, `sourceIsWriteProtected`). Shared uses `FolderInfoService` → `EnhancedFolderInfo` (with `.asFolderInfo`). Mac currently scans twice per run, because shared rescans once `startOperation` copies `sourceURL` in. Use `FolderInfoService` only. Add `videoFileCount`, `isWriteProtected` and `cameraHint` to `EnhancedFolderInfo` if they are missing, and check for them first.
7. **Progress presentation.** iPad reads `shared.progress` (`OperationProgress`) directly. Mac adds interpolation, EMA speed, rolling ETA, per-destination fractions and reused-copy counts through `ProgressViewModel`. Keep the richer model, moved to `Shared/` and fed by the coordinator. Moving iPad onto it is optional and belongs to thesis step 4.

---

## 3. Steps

Each task leaves both apps compiling with `AppCoordinator` still present until Task 9. The approach: move one piece of state into `SharedAppCoordinator` (or a Mac companion), and in the same commit update every reader listed in §1.3. While that happens, `AppCoordinator` keeps a forwarding property with the old name, so views that haven't moved yet still compile. Task 9 retargets the views. Task 10 deletes the file.

### Task 0: Pin current behaviour with tests

**Files:** `BitMatchTests/SharedCoordinatorMacParityTests.swift` (new)

- [ ] Port the behaviours `AppCoordinatorBindingTests` pins to tests against `SharedAppCoordinator` + `SilentPlatformManager` + `InMemoryPhotographerJobStore`, starting with the ones shared already satisfies: start gate rejects a changed source; start gate rejects while analysing; cancellation cancels the prepared card; delayed progress cannot resurrect a completed or cancelled card; compare events never mutate a prepared card. Mark the ones shared does not satisfy yet with `withKnownIssue` and the task that fixes them. **Never skip a test.**
- [ ] Add a verdict-parity test: the same folders through the Mac path and through `SharedAppCoordinator` directly give the same `completionState` and `results`. This closes the "no Mac-vs-iOS verdict-parity test" gap named in the thesis.
- [ ] Build both schemes; run `BitMatchTests`.

### Task 1: One job view model on Mac

**Files:** `Shared/Core/Services/SharedAppCoordinator.swift`, `BitMatch/App/AppCoordinator.swift`, tests

- [ ] Add an optional `photographerJobViewModel: PhotographerJobViewModel? = nil` parameter to `SharedAppCoordinator.init`, used instead of the default `UserDefaults` store when present. iPad call sites are unchanged.
- [ ] Add `.dropFirst()` to the `$sourceURL` sink before `sourceDidChange`. Test: a prepared card from the store survives coordinator init.
- [ ] In `AppCoordinator.init`, build the Core Data `PhotographerJobViewModel` first and pass it into `SharedAppCoordinator(platformManager:photographerJobViewModel:)`. Make `AppCoordinator.photographerJobViewModel` a computed forward to `sharedCoordinator.photographerJobViewModel`. The test-injection path (`sharedCoordinator:` parameter) must use the same instance. Assert it in `AppCoordinatorBindingTests`.
- [ ] Build both schemes; run tests.

### Task 2: Extract SFTP into `MacRemoteBackupController`

**Files:** `BitMatch/Core/Services/MacRemoteBackupController.swift` (new), `AppCoordinator.swift`, `ContentView.swift`, `RemoteBackupDestinationView.swift`, `CopyAndVerifyView.swift`, `TransferPlanView.swift`, `BitMatchTests/RemoteBackupQueueTests.swift`

- [ ] Move `HostTrustPrompt`, `remoteBackupQueue`, the timer, the scheduler flags, `hostTrustPrompt` / `hostTrustContinuation`, and `selectRemoteProfile`, `testRemoteProfile`, `queueRemoteBackup(for:)`, `startRemoteBackupScheduler`, `runDueRemoteBackups`, `armRemoteBackupTimer`, `refreshAll…` / `refreshRemoteBackupSummary`, `confirmHostTrust`, `requestHostTrust`, `pause/retry/cancelRemoteBackup` into the controller. Keep the bodies unchanged. It takes `photographerJobViewModel`, a `results: () -> [ResultRow]` closure (reads `shared.results`), an optional queue, and `startScheduler: Bool`.
- [ ] Move queue construction from `AppCoordinator.init` (lines 445–469), including `store.whenAvailable`, into a `MacRemoteBackupController.makeDefault(store:jobViewModel:)` factory.
- [ ] `AppCoordinator` holds `let remoteBackups: MacRemoteBackupController` and keeps one-line forwards for the old method names, so views still compile.
- [ ] Retarget `RemoteBackupQueueTests.swift:227` to construct the controller directly.
- [ ] Build; run tests (especially the scheduler integration test).

### Task 3: Extract the benchmark estimate into `TransferEstimateModel`

**Files:** `BitMatch/Core/Services/TransferEstimateModel.swift` (new), `AppCoordinator.swift`, `TransferPlanView.swift`

- [ ] Create `@MainActor final class TransferEstimateModel: ObservableObject` with `@Published estimate: TimeEstimate?` and `isCalculating`, and `func update(source:destinations:totalBytes:mode:)`, containing the body of `updateTimeEstimate()`. Add a generation token so a slow, stale benchmark cannot overwrite a newer one. Today it can.
- [ ] `AppCoordinator` owns one and calls `update` from S3, S4 and S5. It forwards `timeEstimate` and `isCalculatingEstimate`.
- [ ] Update `TransferPlanView` to read the model. In Task 6, S3–S5 become subscriptions inside the model on `shared.$sourceURL`, `$destinationURLs` (debounced 500 ms), `folderInfoService` and `$verificationMode`. **Note:** today a change of verification mode does not refresh the estimate. That is a bug; fix it here.
- [ ] Build; run tests.

### Task 4: Report settings live in `SharedAppCoordinator`

**Files:** `Shared/Core/Services/ReportPrefsStore.swift` (new), `SharedAppCoordinator.swift`, `ContentView.swift`, `CopyAndVerifyView.swift`, `TransferPlanView.swift`, `CompareFoldersView.swift`, `MasterReportView.swift`, `PreferencesWindow.swift`; delete `BitMatch/Core/ViewModels/SettingsViewModel.swift`

- [ ] Move `loadPrefs` / `persistPrefs` (same `UserDefaults` keys) into `ReportPrefsStore`. `SharedAppCoordinator` loads `reportSettings` at init and persists on `didSet`. This is decision §2.5.
- [ ] Replace every `coordinator.settingsViewModel.prefs` with `coordinator.sharedCoordinator.reportSettings` in the seven files above. `showOnlyIssues` becomes `@State` in `ContentView`, passed down as the binding it already is.
- [ ] Delete I1's `reportSettings` copy and I2's `onAppear` push.
- [ ] Delete `SettingsViewModel` (its `requestNotificationPermission`, `scheduleNotification`, `toggleReportGeneration` and `updateVerificationMode` have no callers). `toggleCameraDetection` writes `shared.reportSettings.enableAutoCameraDetection`.
- [ ] Build **both** schemes (iPad now persists prefs); run tests; check on iPad and iPhone simulators that report toggles survive a relaunch.

### Task 5: Camera label lives in `SharedAppCoordinator`

**Files:** `git mv BitMatch/Core/ViewModels/CameraLabelViewModel.swift Shared/Core/ViewModels/CameraLabelModel.swift`, `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `CopyAndVerifyView.swift`, `TransferPlanView.swift`, iPad `CopyAndVerifyView.swift`

- [ ] Rename to `CameraLabelModel` and make the settings (`cameraLabelSettings`, same `destLabelSettings` key, persisted on `didSet`, which replaces S7) plus `detectedCamera: CameraType` and `currentFingerprint` owned by `SharedAppCoordinator`. The file already imports only Foundation/SwiftUI and depends only on `Shared/` services; confirm it builds in the iPad target.
- [ ] Replace `SharedAppCoordinator.detectCameraFromSource`'s auto-label with `detectCameraWithMemory` (decision §2.4). Keep the `CameraCard` `detectedCamera` that iPad reads, or migrate its two iPad readers (`CopyAndVerifyView.swift:444`, `:672`) in this commit.
- [ ] Mac: replace `coordinator.cameraLabelViewModel.destinationLabelSettings` / `.detectedCamera` / `.currentFingerprint` with shared. Remove the label part of S3 and I1's label copy (the photographer recipe overlay moves with Task 8). S10's label copy-back becomes a no-op.
- [ ] Build both schemes; run tests; check on iPad and iPhone that the label is suggested and remembered per card.

### Task 6: Selection lives in `SharedAppCoordinator`; Mac volume parts split out

**Files:** `SharedAppCoordinator.swift`, `Shared/Core/Services/FolderInfoService.swift` (if fields are missing), `git mv BitMatch/Core/ViewModels/FileSelectionViewModel.swift BitMatch/Core/ViewModels/MacVolumeAccessModel.swift`, `BitMatch/Core/Services/MacCameraAutoSourceController.swift` (new), `AppCoordinator.swift`, `ContentView.swift`, `HorizontalFlowView.swift`, `CopyAndVerifyView.swift`, `TransferPlanView.swift`, `TransferQueueView.swift`, `ResultsTableView.swift`, `CompareFoldersView.swift`, `PhotographerJobSetupView.swift`, `DevModeManager.swift`, `BitMatchTests/{FileSelectionFetchTests,DestinationDismissalTests,WorkflowSnapshotTests,ComparePickerSelectionTests}.swift`

This is the largest task. Split it into 6a (source/destinations) and 6b (left/right) if the diff gets hard to review; each half compiles on its own.

- [ ] Remove `sourceURL`, `destinationURLs`, `leftURL`, `rightURL`, the folder-info fields and the scan code from the file-selection VM. Everything that read them reads `shared.sourceURL` / `destinationURLs` / `leftURL` / `rightURL` / `sourceFolderInfo` (`EnhancedFolderInfo`, `.asFolderInfo` where a `FolderInfo` is expected) / `isFolderInfoLoading(for:)`. Add the missing `EnhancedFolderInfo` fields (§2.6).
- [ ] Keep only the Mac pieces in `MacVolumeAccessModel`: `VolumeMonitorService` hookup, detected cards and drives, bookmarks, `requestVolumeAccess`, recents, last destinations (S6, now observing `shared.$destinationURLs`), `formattedAvailableSpace`, `detectDriveSpeed`, and `DriveSpeed`. It takes a `weak SharedAppCoordinator` and writes selection changes through it, for example when an ejected backup is removed in `handleBackupDrivesUpdate`. Keep `addDestination` / `removeDestination` as shared methods: move the existing duplicate/safety filtering from the VM into `SharedAppCoordinator`, next to `removeDestinationFolder`.
- [ ] Move S17, `toggleCameraDetection`, `rescanForCameras` and `CameraCardDetectionService` ownership into `MacCameraAutoSourceController(shared:)`. It uses the existing `AutomaticSourceSelectionPolicy` and writes `shared.sourceURL`.
- [ ] Replace `canStartOperation` and `copyAndVerifyPreflightIsReady` with `shared.canStartOperation` / `operationReadinessAssessment`, after merging the stricter rules (§2.3) into shared. Tests: blocked while analysing; blocked below `sourceSize + 100 MB`.
- [ ] Delete S1, S2, S8, I1's selection copies and S10's selection copy-back. Move S4 and S5 into `TransferEstimateModel` (Task 3 note).
- [ ] `ContentView.idealWindowHeight` reads `shared.destinationURLs.count` and `shared.sourceURL`. The window-sizing logic is otherwise unchanged.
- [ ] Retarget the four test files. `FileSelectionFetchTests` becomes `FolderInfoService` tests; `DestinationDismissalTests` stays on `MacVolumeAccessModel`.
- [ ] Build both schemes; run tests; on Mac, check drag-and-drop, auto-detected card selection, ejecting a backup, and relaunch restoring last destinations.

### Task 7: Progress presentation lives in `Shared/`

**Files:** `git mv BitMatch/Core/ViewModels/ProgressViewModel.swift Shared/Core/ViewModels/ProgressPresentationModel.swift`, `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `HorizontalFlowView.swift`, `TransferQueueView.swift`, `ResultsTableView.swift`, `CompareFoldersView.swift`, `DevModeManager.swift`

- [ ] Make `SharedAppCoordinator` own `let progressPresentation = ProgressPresentationModel()`. Feed it in the executor's `onProgress` callback (S11's mapping, with a 120 ms presentation throttle and the `lastSharedBytesProcessed` delta logic kept as private coordinator state) and in the `operationState` transitions (S14's timer start/stop and the "Preparing transfer…" message). Call `progressPresentation.reset()` from `resetForNewOperation()`.
- [ ] The per-destination guard in S11 compares against `fileSelectionViewModel.destinationURLs.count`. Use `destinationURLs.count` from the run's config instead, so a later selection change cannot break it.
- [ ] Views `@ObservedObject` the progress model directly. Drop S9 and the `progressPercentage`, `currentFileName`, `formattedSpeed` and `formattedTimeRemaining` forwards. **Note:** shared already has `progressPercentage` / `formattedSpeed` / `formattedTimeRemaining` computed from `OperationProgress`. Mac views must use the presentation model's versions (`displayProgress`, rolling rate) to keep today's Mac display. Don't silently swap them.
- [ ] iPad: no change is required (it can keep reading `shared.progress`). Adopting the model there is thesis step 4.
- [ ] Build both schemes; run tests; on Mac, check that the speed, ETA and per-destination bars move during a real copy.

### Task 8: One project lifecycle and one mode

**Files:** `SharedAppCoordinator.swift`, `AppCoordinator.swift`, `ContentView.swift`, `CopyAndVerifyView.swift`, `BitMatchTests/AppCoordinatorBindingTests.swift` → `SharedCoordinatorMacParityTests.swift`

- [ ] Make `startProjectOperation()` the single entry point for a prepared project card on all platforms. Before it runs, fold in Mac's extra gate: `photographerJobViewModel.isStartEligible(preflightReady:sourceURL:destinationCount:verificationMode:)`. Also apply the photographer recipe via `PhotographerDestinationResolver.operationSettings(base:renderedRecipe:)` to the run's camera settings. Today only `AppCoordinator` calls the resolver (I1); `SharedAppCoordinator.startProjectOperation()` does not, so iPad/iPhone project cards appear to run without the job's folder recipe. Confirm with a test, then fix it for both platforms here. (iPad gates on `startPresentation(...)`, the counterpart of Mac's `isStartEligible`; keep both consistent.)
- [ ] Carry over Mac's "rejected start ends the card in issues" (lines 104–106) when `startOperation` returns without the card leaving `.notStarted`.
- [ ] Delete from `AppCoordinator`: `configurePhotographerReportLifecycle`, the unused `makePhotographerReportContext`, S12, S14's lifecycle half, and S15's forward (views observe the VM). `AppCoordinator.startOperation()` becomes: `.copyAndVerify` → `startProjectOperation()` if a card is prepared, else `startOperation()`; `.compareFolders` → `compareFolders()`.
- [ ] Delete `AppCoordinator.currentMode`. Bind `ModeSelectorView(mode:)` to `$shared.currentMode` and route `switchMode` to shared. Delete S10 and, if nothing else observes it, the `BitMatchQueuedTransferSelected` post.
- [ ] Move the remaining `AppCoordinatorBindingTests` into the parity suite and remove their `withKnownIssue` markers from Task 0. Every one must pass.
- [ ] Build both schemes; run tests; on Mac, run one ordinary copy, one prepared project card, one cancelled card, and one queued-transfer replay.

### Task 9: Retarget Mac views to `SharedAppCoordinator`

By now `AppCoordinator` holds only forwards plus references to the companions (`remoteBackups`, `estimate`, `volumeAccess`, `cameraAutoSource`). Retarget views leaf-first, one commit each if preferred. Every view changes `@ObservedObject var coordinator: AppCoordinator` to `SharedAppCoordinator` and receives whichever companions it needs, either as parameters or as `@EnvironmentObject`. Use environment objects for `MacRemoteBackupController` and `MacVolumeAccessModel`, which are used several levels down.

- [ ] `MasterReportView` (S only)
- [ ] `RemoteBackupDestinationView`, `RemoteBackupDestinationManager` (J + R)
- [ ] `PhotographerJobSetupView` (J + shared source)
- [ ] `ResultsTableView`, `TransferQueueView` (shared + progress model)
- [ ] `CompareFoldersView`
- [ ] `TransferPlanView`, `TransferOptionsView` (+ estimate model, R)
- [ ] `HorizontalFlowView` (+ `MacVolumeAccessModel`)
- [ ] `CopyAndVerifyView`
- [ ] `PreferencesWindow`, `PreferencesWindowController(coordinator:)`, preview (build a `SharedAppCoordinator` with an in-memory Core Data job VM, plus `MacCameraAutoSourceController`)
- [ ] `DevModeManager`: delete the seven `AppCoordinator` overloads; callers use the existing `SharedAppCoordinator` ones
- [ ] `ContentView`: `@StateObject var coordinator: SharedAppCoordinator`, plus `@StateObject`s for the four companions, built in `init` from one `MacAppEnvironment.make()` factory that wires the Core Data store, job VM and SFTP queue. Also: host-trust alert → `remoteBackups.hostTrustPrompt`; `TransferLibraryView(coordinator: coordinator, …)`; window sizing reads shared (§1.4).
- [ ] After each view: build the Mac scheme; resize the window from compact to wide; check the view with keyboard only and without hover.

### Task 10: Delete `AppCoordinator`

**Files:** delete `BitMatch/App/AppCoordinator.swift`; update comments in `FileSelectionViewModel`/`MacVolumeAccessModel.swift:143`, `CameraCardDetectionService.swift:255`, `CompareFoldersView.swift:1`; update `ARCHITECTURE.md`, `docs/THESIS.md` (mark step 3 done, fix the "676 lines" finding), and `CHANGELOG.md`

- [ ] `rg -n '\bAppCoordinator\b' --glob '!**/SharedAppCoordinator*'` returns only historical plan/spec docs.
- [ ] Rename `WorkflowSnapshotTests.appCoordinator` usage to drive `SharedAppCoordinator` + companions.
- [ ] Build `BitMatch` and `BitMatch-iPad` (Debug and Release); run `BitMatchTests` and `BitMatch-iPadTests`; run `./test.sh`.
- [ ] Manual pass on a Mac with a real card and two backups: copy, verify, report, ASC MHL, history, compare, master report, SFTP queue with host-key prompt, preferences round-trip, relaunch. Record whether this was simulator/build validation or a physical-device run.

---

## 4. Risks

- **Test-injection seams.** `AppCoordinator.init` has six injection points (`photographerJobViewModel`, `fileSelectionViewModel`, `platformManager`, `remoteBackupQueue`, `startRemoteScheduler`, `sharedCoordinator`), which tests rely on. Each needs an equivalent on `SharedAppCoordinator` or a companion before the test moves. Tasks 1, 2 and 6 add them.
- **Nested observables.** SwiftUI does not re-render when a nested `ObservableObject` changes. `SharedAppCoordinator` already forwards `folderInfoService` and `transferJournal`. The progress model, label model and job VM must be observed directly by the views that read them, not through `coordinator.x.y`. A missed one fails silently: the view shows stale values. That breaks promise 2, so check every retargeted view during a live run.
- **Throttling.** S11's 120 ms throttle guarded Mac rendering cost. It moves into the coordinator in Task 7; keep it.
- **iPad behaviour changes** (§2.3, 2.4, 2.5) are deliberate but visible. Call them out in the changelog and check them on iPhone and iPad simulators, not only the Mac.
- **Size.** Expect about −680 lines from `AppCoordinator`, about −120 from `SettingsViewModel`, and about −300 of duplicate scanning and readiness code in the file-selection VM. The companions add about 450, mostly moved SFTP code.
