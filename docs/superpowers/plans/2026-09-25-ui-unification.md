# UI Unification Implementation Plan (thesis step 4)

> **For agentic workers:** Use superpowers:executing-plans (or subagent-driven-development) to carry this out task by task. Steps use checkbox (`- [ ]`) syntax. Each task must build the `BitMatch` (macOS) and `BitMatch-iPad` schemes and pass `BitMatchTests` and `BitMatch-iPadTests` before it is committed. Every UI task also needs a check at iPhone width (<600 pt), iPad split view (600–959 pt), and a resizable Mac window from its 580 pt minimum to wide.

**Goal:** Replace each pair of Mac and iPad/iPhone screens with one SwiftUI screen in `Shared/`, so the Compare, Setup, Progress, Completion and History flows *behave* the same on every device and only their layout adapts. This is step 4 of [docs/THESIS.md](../../THESIS.md). It serves promise 5 ("layout adapts; behavior does not") and, through the readiness and verdict fixes, promises 1–4.

**Status:** Plan only. It was written without Xcode, so nothing here has been compiled. Line numbers refer to `main` at `08bae3f`.

**Related plans:** [2026-09-25-retire-appcoordinator.md](2026-09-25-retire-appcoordinator.md), which is step 3 and is still only on branch `origin/claude/retire-appcoordinator-plan`. Its task numbers are cited below as **R1–R10**. Thesis step 2 (one operation state, with the verdict derived from results) is cited as **S2**.

---

## 0. Ground rules

### 0.1 Where shared UI lives and how it is built

- `Shared/` is compiled into both app targets. `BitMatch/` is compiled into the Mac target only, and `BitMatch-iPad/` into the iOS target only. `Platforms/` is iOS-only apart from `MacOSPlatformManager.swift` (`BitMatch.xcodeproj/project.pbxproj:49-55,204-207,273-277`). Every file under `Shared/` must therefore compile without AppKit or UIKit, or wrap those APIs in `#if os(...)`.
- **Shared screens take values and closures, not a coordinator.** Each shared screen is a view over a presentation struct plus an actions struct, for example `CompareScreen(presentation: ComparePresentation, actions: CompareActions)`. Each platform keeps a thin *adapter* view that builds the presentation from its coordinator: `AppCoordinator` on Mac today, `SharedAppCoordinator` on iOS. This is what lets Compare, Completion, History and parts of Setup ship **before** `AppCoordinator` is retired. After R10 the two adapters are identical and collapse into one. The screens also become testable as pure values.
- Presentation structs and readiness rules go in `Shared/Core/Models/` as pure, `Sendable`, `Equatable` functions. Screens go in `Shared/Views/<Flow>/`.
- **Names must not collide.** A type in `Shared/` is visible in both targets, and these names are already taken: `CompareFoldersView` (Mac `BitMatch/Views/CompareFoldersView.swift:5` and iPad `ModularContentView.swift:177`), `MasterReportView` (Mac `MasterReportView.swift`, iPad `ModularContentView.swift:486`), `CopyAndVerifyView` (both targets), `TransferQueueView` (Mac `CompactTransfer/TransferQueueView.swift`, iPad `OperationProgressView.swift:407`), `StatView` (Mac `MasterReport/Components/StatView.swift`, iPad `OperationProgressView.swift:218`), `MasterReportScanningView` (both targets). Shared screens therefore get new names (`CompareScreen`, `SetupScreen`, `ProgressScreen`, `OutcomeScreen`, `MasterReportScreen`). The old types are deleted in the same commit that stops using them.
- **Width decides layout.** Use `AdaptiveNavigationPolicy` (`Shared/Core/Models/AdaptiveNavigationPresentation.swift:11-24`: `.compact` <600, `.toolbar` 600–959, `.sidebar` ≥960) for every screen. Measure with the screen's own available width, not the device idiom and not `horizontalSizeClass`. The Mac window minimum is 580 pt (`BitMatch/Views/WindowPresentationPolicy.swift:7`), so a narrow Mac window gets the compact layout. That is intended, and it gives the iPhone layout a desktop test bed.
- Move the Mac-only width policies (`HeaderPresentationPolicy`, `ResultTableLayoutPolicy`, `TransferCardLayoutPolicy`, `MasterReportLayoutPolicy`, `RemoteDestinationLayoutPolicy`, `AdaptiveWorkbenchLayout`) into `Shared/Core/Models/` when a shared screen first needs them. They import only CoreGraphics.
- Touch and no hover: every action needs a ≥44 pt target on iOS. No essential information may depend on hover. The Mac `TransferQueueView` rows use hover and `NSCursor`, and that stays Mac-only decoration.
- Styling: the Mac uses `BitMatch/UI/DesignSystem.swift` and `Card.swift` (Mac target), and iOS uses `Color(hex:)` from `BitMatch-iPad/ContentView.swift:5`. The first shared screen adds a small `Shared/Views/Style/BitMatchStyle.swift` (colours, corner radii, card background). **Do not** declare a second `Color(hex:)` in `Shared/`, because it would clash with the iPad one. Move the iPad extension into the style file instead.

### 0.2 Files that are off limits until the Mac session lands them

A Mac session is rewriting `SharedAppCoordinator.swift`, `OperationStateService.swift`, `OperationStateMachine.swift`, `CopyVerifyExecutor.swift`, `BitMatch/App/AppCoordinator.swift` and `CompletionVerdict*.swift` (S2). Each step below says whether it touches them:

- A step marked **no locked files** can start now.
- A step marked **after S2** must wait until that work is merged.
- A step marked **after R*n*** must wait for that task of the retire-AppCoordinator plan.

Where a rule belongs in `SharedAppCoordinator` eventually (for example `canStartOperation`), this plan puts the rule in a new pure model first. The adapters call that model, and a later one-line change makes the coordinator call it too.

### 0.3 Test discipline

Each test that claims to guard a behaviour lists **Plant:** a one-line production change that must make it fail. Whoever runs the step plants that change, sees the test go red, and reverts it.

---

## 1. Compare

### 1.1 Implementations

**Shared already:**
- `SharedAppCoordinator.compareFolders()` (`SharedAppCoordinator.swift:666-738`), `lastCompareStats` (`:95`), with `leftURL`/`rightURL` whose `didSet` clears stats (`:82-87`).
- `ComparisonCoordinator.swift:29-161`, which ignores Finder metadata (`:147-150`) and destination-only offload manifests (`:156-161`).
- `Shared/Views/CompareResultsView.swift:7-126`, rendered by both platforms, and its `CompareReportDocument` (`:128-185`).
- `canStartOperation`'s compare branch (`SharedAppCoordinator.swift:807`): `leftURL != nil && rightURL != nil && !isOperationInProgress`. Neither compare view uses it.

**Mac:**
- `BitMatch/Views/CompareFoldersView.swift:5-339`: folder cards with `Card(onDrop:)` (`:54`, `:88`), a verification-mode radio list (`:143-247`), an action section (`:250-269`) and `openFolderPanel` (`:332-338`).
- Selection state lives in `FileSelectionViewModel.leftURL/rightURL` (`:13-23`). `canCompare` (`:428-430`) is mirrored into shared by `AppCoordinator.swift:479-486`.
- The button uses `.disabled(!coordinator.canStartOperation)` (`CompareFoldersView.swift:266-267`, `AppCoordinator.swift:46-52`).
- During the run, progress and Cancel come from `ResultsTableView` (`:198-222`) via `ContentView.resultsArea` (`ContentView.swift:189-203`).
- After the run, `ContentView.mainContentSwitch` (`:177-187`) replaces the whole mode view with `completionView` (`:284-314`).

**iPad/iPhone:**
- `BitMatch-iPad/Views/ModularContentView.swift`: `CompareFoldersView` (`:177-235`), `FolderSelectionCard` (`:250-371`), `ComparisonControlsView` (`:373-429`) and `ComparisonProgressView` (`:431-480`).
- Routing:
  - iPad: `ModularContentView.mainContentArea` (`:82-100`).
  - iPhone: `PhoneContentView.swift:28-40`.
- Pickers: `Platforms/iOS/Services/IOSFileSystemService.swift:29-36,137`.

### 1.2 Behaviour differences

1. **Compare readiness.**
   - Mac enables Compare on `leftURL != nil && rightURL != nil`. It has no in-progress term; instead it hides the card while a run is going (`CompareFoldersView.swift:107`).
   - iOS has no disabled state. `ComparisonControlsView` exists only when both URLs are set (`ModularContentView.swift:217`), and its button calls `compareFolders()` directly (`:407-410`).
   - Mac ⌘R (`ContentView.swift:505-509`, menu at `BitMatchApp.swift:95-98`) starts without any readiness check and relies on the coordinator's alert (`SharedAppCoordinator.swift:668-673`).
2. **Same or nested folders.** Neither platform blocks comparing a folder with itself or with its own parent or child. The same folder reports "Folders match", which is a false green (promise 2).
3. **Waiting for folder info.** Neither platform waits for the left/right info to load. Copy does wait.
4. **Progress while comparing.**
   - Mac: card progress plus the transfer `ResultsTableView`. Its empty state says "Files will appear here as they are copied and verified" (`ResultsTableView.swift:308-313`), and its Issues Only toggle does nothing because `results` is empty.
   - iPad at ≥600 pt: the generic transfer `OperationProgressView` (`ModularContentView.swift:83`), with transfer-style Pause.
   - iPhone: the compare-specific `ComparisonProgressView`.
5. **The outcome screen.**
   - Mac replaces Compare with `completionView`, which is only a "New transfer" button. The verdict message (`SharedAppCoordinator.swift:712-722`) is never shown. `CompareResultsView` appears only after the user presses "New transfer".
   - iPad shows the *transfer* `CompletionSummaryView` (`ModularContentView.swift:89`). There, "Export report" throws `noFinishedTransfer` (`SharedAppCoordinator.swift:743-748`), and "New transfer" clears the copy source and destinations (`CompletionSummaryView.swift:324-327`).
   - iPhone shows `CompareResultsView` immediately. A failed or cancelled compare silently returns to selection.
6. **Mode switch mid-run.** iPhone keeps the mode menu live during a compare, and the menu writes `currentMode` directly (`HeaderTabsView.swift:64-66`). The Mac hides its selector (`ContentView.swift:215`). On iPad, navigation sits inside `IdleStateView`.
7. **Verification mode.** The Mac shows a top-level expandable radio list with MHL badges and calls `saveVerificationMode` (`CompareFoldersView.swift:143-247`). iOS shows a top-level `.menu` picker (`ModularContentView.swift:385-390`). Both are outside any "Advanced" section (see §6).
8. **Picking folders.**
   - The Mac uses `NSOpenPanel` or drag-and-drop. `Card.swift:421-447` accepts directories only and silently ignores anything else.
   - iOS uses a document picker. A card whose info failed to load shows "Select Folder" but ignores taps (`ModularContentView.swift:276-283`).
9. **Cancel wording.** On every platform the toast says "User cancelled transfer" (`ContentView.swift:137`, `ModularContentView.swift:33`).
10. **Copy.** The right folder is "RIGHT FOLDER (TO VERIFY)" on the Mac and "To compare" on iOS. The button is "Compare folders" with `checkmark.shield` on the Mac and "Compare Folders" with `magnifyingglass` on iOS.
11. **iPhone layout.** Two `FolderSelectionCard`s sit in a fixed `HStack` (`ModularContentView.swift:191`), so each is about 150 pt wide on an iPhone.

### 1.3 Proposed shared component: `CompareScreen`

**Model (`Shared/Core/Models/ComparePresentation.swift`):**

```swift
enum CompareReadiness: Equatable, Sendable {
    case needsLeft, needsRight
    case loading                     // left or right folder info still loading
    case blocked(reason: String)     // same folder, nested, unreadable
    case ready
    case running
}
struct ComparePresentation: Equatable, Sendable {
    let left: FolderSlotPresentation     // name, path, file count, size, isLoading, error
    let right: FolderSlotPresentation
    let readiness: CompareReadiness
    let phase: ComparePhase              // .setup, .running(progress), .finished(CompareOutcome)
    let verificationSummary: String      // one line, e.g. "Checksums · SHA-256"
    static func make(left: URL?, right: URL?, leftInfo:…, rightInfo:…, isRunning: Bool,
                     operationState: OperationState, stats: CompareStats?, mode: VerificationMode) -> Self
}
enum CompareOutcome: Equatable, Sendable { case match(CompareStats), differ(CompareStats), cancelled, failed(String) }
```

The logic that moves out of views:
- The readiness expression from `CompareFoldersView.swift:266` and `ModularContentView.swift:217`.
- A **new** same/nested check using `SafetyValidator.destinationSafetyIssue(source:destination:)`, which already detects "is the source / inside / contains" (`SafetyValidator.swift:196-217`).
- The loading gate.
- The outcome text: `compareFolders` builds it inline (`SharedAppCoordinator.swift:712-722`). The model re-derives it from `CompareStats`, so the coordinator string is no longer what users read.
- "Which screen is showing".

**Actions:** `pickLeft`, `pickRight`, `clearLeft`, `clearRight`, `dropLeft(URL)?`, `dropRight(URL)?`, `compare`, `cancel`, `compareAgain`, `setVerificationMode`, `export(CompareReportDocument)`. The drop actions are nil where drag-and-drop is not offered. SwiftUI `.dropDestination(for: URL.self)` works on iPadOS too, so the iPad *could* gain drop in a later task; this plan doesn't require it.

**Layout:**
- `.compact` (iPhone, narrow Mac): folder slots stacked vertically, full-width Compare button, results below.
- `.toolbar` and `.sidebar`: slots side by side. In `.sidebar`, results sit in a column beside the slots once a compare has finished.
- Progress is inline in the screen (from `ComparisonProgressView`) on all widths. The transfer progress/outcome screens are never used for compare.
- The verification-mode picker sits inside the screen's "Advanced" disclosure (§6), with the one-line summary above it.

### 1.4 Decisions for Mike

- **C-1.** Should a same-folder or nested compare be *blocked* (recommended) or only warned?
- **C-2.** Should the mode switcher be disabled during any running operation on iPhone, as it is on the Mac and iPad (recommended)?

---

## 2. Completion / Report

### 2.1 Implementations

**Shared already:**
- `CompletionVerdict.resolve` (`Shared/Core/Models/ResultPresentation.swift:64-90`).
- `CompletionVerdictPresentation.make(_:)` and the state-aware `make(state:rows:hasErrors:hasCriticalErrors:)` (`Shared/Core/Models/CompletionVerdictPresentation.swift:9-64`), which labels `.cancelled` plainly (`:43-50`).
- `DestinationResultSummary.make` (`ResultPresentation.swift:147`), `ResultPresentation.visibleRows` (`:111`).
- `SharedAppCoordinator.showsOutcomeSummary` (`:262-269`), `completionExportDocument` (`:743`), `resetForNewOperation` (`:757-765`).
- Report and ASC MHL writing in `CopyVerifyExecutor` (`:279-289,327-383`) and `ReportExporter.autoSaveReports` (`:416-521`). This writes to `<first destination>/Reports/`. On iOS the PDF is skipped (`:220-227`).

**Mac:**
- `ContentView.mainContentSwitch` (`ContentView.swift:177-187`) and `completionView` (`:284-314`): "New transfer" plus `PhotographerSessionDashboard`, gated by `CompletionEvidencePresentation` (`BitMatch/Views/Photographer/CompletionEvidencePresentation.swift:1-5`).
- `ResultsTableView.swift`: verdict banner (`:19-31,94-122`), destination summaries (`:77-92`), stats (`:161-176`), Issues Only (`:225-233`), and `completionTint` (`:518-527`).

**iPad/iPhone:**
- `BitMatch-iPad/Views/CompletionSummaryView.swift`: screen (`:5-76`), header (`:80-117`), stats (`:121-177`), `ErrorDetailsView` (`:214-297`) and actions (`:301-356`).
- Routed from `ModularContentView.swift:89-90` and `PhoneContentView.swift:75-76`.

### 2.2 Behaviour differences

1. **Guidance for cancelled and failed runs (the example in the brief).**
   - `CompletionSummaryView.swift:281` uses `CompletionVerdictPresentation.make(verdict).sourceGuidance`, built from the verdict alone.
   - A cancelled run resolves to `.issues` (`ResultPresentation.swift:80-82`). The header, which is state-aware, therefore says "Keep source media intact until a transfer completes." The orange `ErrorDetailsView` below it then says "Review failed files before clearing source media", and it counts unfinished rows as "failed file results". The two pieces of guidance contradict each other.
   - A completed transfer with issues also gets the generic `.issues` text, where the Mac shows "Review results and handoff records…".
   - The Mac uses the state-aware presentation throughout (`ResultsTableView.swift:25,110-115`).
2. **Colour.**
   - The Mac maps the SF Symbol name to a colour (`ResultsTableView.swift:518-527`), so a cancelled run is **red**.
   - iOS maps the verdict to a colour (`CompletionSummaryView.swift:8-15,93-98`), so a cancelled run is **orange**.
3. **Counts.**
   - The Mac shows files completed/total, matches, and "Reused N" from the Mac-only `ProgressViewModel` (`ResultsTableView.swift:161-176,243-270`).
   - iOS shows files processed from `progress`, average speed, verification mode, and "Data Copied". That last figure is the *source folder size*, not verified bytes (`CompletionSummaryView.swift:136-167`).
   - "Reused" is always absent because the engine sends `reusedCopies: nil` (`SharedFileOperationsService.swift:630,694,775`).
4. **Duration.** iOS shows "Completed in X" (`:109-111`), even for cancelled and failed runs. The Mac shows no duration.
5. **File list.** The Mac has an Issues Only filter, persisted through `SettingsViewModel.showOnlyIssues`, and a "No issues found" empty state. iOS has no filter and shows a 1,000-row cap note (`:40,48-51`).
6. **Export.** The Mac completion screen has no export: users must open Transfers and export from there. iOS has an "Export report" menu for JSON or CSV (`:316-355`). Neither platform says where the auto-saved report was written.
7. **New transfer.** On the Mac it keeps source and destinations (`ContentView.swift:288-292`). On iOS it clears them (`CompletionSummaryView.swift:325-327`).
8. **Project evidence.** The Mac shows `PhotographerSessionDashboard` with remote-backup actions on the completion screen. iOS shows nothing on completion; `MobileProjectEvidenceView` appears only in setup (`BitMatch-iPad/Views/CopyAndVerifyView.swift:109-115`).
9. **Compare runs.** iPad renders this transfer summary for compare runs (§1.2.5).
10. **Reports.** The Mac writes a PDF, CSV, JSON and SHA-256 sidecar. iOS writes no PDF.
    - This is a real platform limitation of `ReportView` rendering, which is AppKit (`ReportExporter.swift:220-227`).
    - But the report toggle on both platforms says "Create PDF & CSV report(s)".
    - The iOS Settings toggle says "PDF & JSON" (`ModularContentView.swift:1079`).
    - The label must say what each platform actually writes (promise 3).

### 2.3 Proposed shared component: `OutcomeScreen`

**Model (`Shared/Core/Models/TransferOutcomePresentation.swift`, a new file, so no locked file is edited):**

```swift
enum OutcomeTone: Sendable { case verified, needsReview, failed, cancelled }
struct TransferOutcomePresentation: Equatable, Sendable {
    let verdict: CompletionVerdictPresentation   // always the state-aware make(state:…)
    let tone: OutcomeTone                        // from state + verdict, never from a symbol name
    let guidance: String                         // exactly one source of truth
    let issueLines: [String]                     // "N files need attention", errors, warnings; empty when cancelled
    let durationLabel: String?                   // "Completed in …" / "Stopped after …"
    let fileCounts: (verified: Int, needsAttention: Int, notReached: Int)
    let bytesVerified: Int64?                    // from results; nil rather than the source size
    let destinations: [DestinationResultSummary]
    let rows: [ResultRow]; let rowsTruncated: Bool
    let reportLocation: URL?                     // where autoSaveReports wrote, when known
    let reportFormatsDescription: String         // "PDF, CSV and JSON" on Mac, "CSV and JSON" on iOS
    let showsProjectEvidence: Bool               // CompletionEvidencePresentation, moved to Shared
    static func make(state: OperationState, rows: [ResultRow], hasErrors: Bool,
                     hasCriticalErrors: Bool, errorCount: Int, warningCount: Int,
                     duration: TimeInterval?, reportLocation: URL?, …) -> Self
}
```

The logic that moves out of views:
- Guidance: Mac `ResultsTableView.swift:110-115` and iOS `CompletionSummaryView.swift:281`.
- Tint: `ResultsTableView.swift:518-527` and `CompletionSummaryView.swift:93-98`.
- Issue lines: `CompletionSummaryView.swift:239-279`.
- Counts and bytes.
- Duration wording.
- The truncation note.
- The empty state for Issues Only.

Also move `CompletionEvidencePresentation` to `Shared/Core/Models/`. If S2 changes `CompletionVerdict`, `make` consumes whatever it produces. This struct only *presents* a verdict and never decides one.

**Actions:** `newTransfer`, `export(asCSV:)`, `revealReport` (Mac: `NSWorkspace.activateFileViewerSelecting`; iOS: share sheet for the report file; nil when the location is unknown), `retryFailed` (routes to the existing `retryTransfer` for the journal record), and project-evidence actions (Mac: queue/retry/cancel remote backup).

**Layout:**
- `.compact`: verdict header, guidance, issue lines, destination summaries, actions, then a collapsed file list.
- `.toolbar`: the same order, with destination summaries in a two-column grid.
- `.sidebar`: verdict, guidance and actions in a leading column; destinations and the file list in the trailing column.
- The Issues Only filter is available on all widths.

### 2.4 Decisions for Mike

- **O-1.** Should "New transfer" keep the source and backups (the Mac behaviour) or clear them (the iOS behaviour)? Recommended: **clear the source and keep the backups**. The next card usually goes to the same drives, and keeping the old source risks re-copying the same card by accident.
- **O-2.** Should Retry and Export move onto the completion screen on the Mac? Recommended: yes.

---

## 3. Progress

### 3.1 Implementations

**Shared already:**
- Engine emits every 0.5 s (`SharedFileOperationsService.swift:438`).
- `SharedAppCoordinator.progress` (`:54`, set at `:462-469`), `progressPercentage`/`formattedSpeed`/`formattedTimeRemaining` (`:813-823`), `canPause`/`canResume`/`isPaused` (`:875-885`), and pause/resume/cancel (`:559-620`).
- `OperationProgress` and `ProgressStage` (`OperationModels.swift:108-240`), and `TransferOperationPresentation` (header title).

**Mac:**
- `AppCoordinator` copies `progress` into the Mac-only `ProgressViewModel` (`AppCoordinator.swift:556-578,596-637`).
- `ProgressViewModel.swift` (interpolation, EMA, ETA, per-destination fractions).
- Views: `CopyAndVerifyView.compactOperationView` (`CopyAndVerifyView.swift:101-157`), `TransferQueueView.activeTransfer` (`CompactTransfer/TransferQueueView.swift:265-298`), `CompactTransferCard.swift`, and `ContextualDestinationPopup` (`TransferQueueView.swift:93`).
- Menu ⌘R and ⌘. (`BitMatchApp.swift:94-105`).

**iPad/iPhone:**
- `BitMatch-iPad/Views/OperationProgressView.swift`: header (`:97`), display (`:158`), controls (`:240-295`), current file (`:318`), destination queue (`:407-486`).
- Keep-awake, background time and Live Activity come from `IOSBackgroundTaskService.swift:58-157,250-275`.

### 3.2 Behaviour differences

1. **Stage and bar.**
   - `operationState` stays `.inProgress` for the whole copy and verify, because the engine never sends `.copying`.
   - The Mac maps `.inProgress` to `.preparing` (`TransferQueueView.swift:268-276`), and `CompactTransferCard` draws the bar only for `.copying`/`.verifying` (`CompactTransferCard.swift:236`). So **during a normal run the Mac card reads "Preparing…" with no bar, percentage, speed or ETA.**
   - iOS draws the bar and labels each destination row from `progress.currentStage` (`OperationProgressView.swift:84-92`).
   - This is the most visible behaviour gap.
2. **Percentage.**
   - The Mac uses files copied / total, interpolated on a 0.25 s timer (`ProgressViewModel.swift:69,215-250`). It reaches about 100% when copying ends and sits there through verification.
   - iOS uses the engine's `(copied + verified) / (files × stages)`.
3. **Speed and ETA.**
   - The Mac uses an EMA with τ = 3 s and rolling windows (`ProgressViewModel.swift:266-272,337-349`), shown in decimal MB/GB.
   - iOS uses the engine's cumulative average, which includes paused time, and `.file` formatting (`OperationModels.swift:171-184`).
   - Neither ETA accounts for the verify stage.
4. **Per destination.**
   - The Mac copies the overall fraction to every destination when the counts don't match (`ProgressViewModel.swift:381-393`). It also shows fake "fast lane" icons by index (`CompactTransferCard.swift:420-430`).
   - iOS shows a real bar per destination, with a done/total count and path (`OperationProgressView.swift:60-82`).
5. **Current file.** The Mac shows the path of the last *result* row (`TransferQueueView.swift:392-398`), which lags. iOS shows `progress.currentFile` (`OperationProgressView.swift:318-349`).
6. **Pause/resume.**
   - The Mac has one toggle (`CopyAndVerifyView.swift:126-133`). iOS has two buttons (`OperationProgressView.swift:253-291`).
   - On the Mac, `.resuming` triggers `startProgressTracking()` → `reset()` (`AppCoordinator.swift:600-601`, `ProgressViewModel.swift:66`) but leaves `lastSharedBytesProcessed`, so byte totals and ETA are wrong after a resume.
   - `operationState` stays `.resuming` until the run ends (`SharedAppCoordinator.swift:615`), because the coordinator never observes `OperationStateService`'s later move to `.inProgress`. **S2 owns this.**
7. **Automatic pause.** Background, low-battery and Mac-sleep pauses call only `stateService.pauseOperation(currentProgress: nil)` (`OperationStateService.swift:259-285`). The engine keeps copying, yet `canResume` becomes true, so iPad shows a Resume button during a live copy. **S2 owns this**; the shared progress screen must read the single state S2 produces.
8. **Cancel.** Neither platform asks for confirmation. Mac ⌘. is never disabled (`BitMatchApp.swift:102-105`), and when nothing is running it still sets `.cancelled` and shows the toast. iPhone shows no cancel toast (only `ModularContentView.swift:56` does).
9. **iOS-only keep-awake and background.**
   - The "Keep Awake On" and "Background ~N m left" pills (`OperationProgressView.swift:120-150`) read computed pass-throughs that nothing publishes (`SharedAppCoordinator.swift:113-114`), so they refresh only incidentally.
   - The Live Activity has no widget UI in the repo.
   - The Mac takes no sleep-prevention assertion.
10. **Layout gaps.** iPad does not wrap the progress view in a `ScrollView` (`ModularContentView.swift:85`), so many destinations clip in a short split view. iPhone does wrap it.
11. **Queue.** The Mac `TransferQueueView` "Queued"/"Completed" sections are DEBUG fakes (`:430-470`). Neither platform shows the real journal queue during a run.

### 3.3 Proposed shared component: `ProgressScreen`

**Model:** `ProgressPresentationModel`, which is Mac `ProgressViewModel` moved to `Shared/` by **R7**. It is fed by the coordinator, plus a pure `TransferProgressPresentation` snapshot:

```swift
struct TransferProgressPresentation: Equatable, Sendable {
    let title: String                  // from the single S2 state + progress.currentStage, never .inProgress→"Preparing"
    let stage: ProgressStage           // copying / verifying / writing handoff record
    let fraction: Double               // one definition on all platforms: engine (copied+verified)/(files×stages), smoothed
    let speed: String?; let eta: String?   // one method (EMA over active time, excludes pauses), one formatter
    let currentFile: String?           // progress.currentFile
    let destinations: [DestinationProgressRow]   // from OperationProgressView.swift:60-92 rules, moved to Shared
    let controls: ProgressControls     // canPause, canResume, canCancel (new: false when nothing is running)
    let deviceNotes: [String]          // iOS keep-awake / background-time text; empty on Mac
}
```

**Actions:** `pause`, `resume`, `cancel` (optionally confirmed, see P-1), `openDestinationDetail(id)`.

**Layout:**
- `.compact`: header, bar, speed/ETA row, current file, destination rows, controls pinned at the bottom (≥44 pt).
- `.toolbar`: the same, with speed, ETA and elapsed in one row.
- `.sidebar`: header and bar across the top, destination rows in a grid.
- Always inside a `ScrollView`.
- Destination detail opens as a sheet or popover anchored to the row, not at a fixed position (the Mac currently uses `.position(x:300,y:150)`).
- Mac hover is decoration only.

### 3.4 Decisions for Mike

- **P-1.** Should Cancel ask for confirmation? Recommended: yes, one confirmation, because cancelling a multi-hour offload by accident is costly.
- **P-2.** Should the Mac take a sleep-prevention assertion (`ProcessInfo.beginActivity`) while copying, to match iOS keep-awake? Recommended: yes, as a separate small change.

---

## 4. Setup (copy and verify)

### 4.1 Implementations

**Shared already:**
- `SharedAppCoordinator.operationReadinessAssessment` (`:1009-1078`), `canStartOperation` (`:802-812`), `verificationMode` (`:34`, persisted), `generateASCMHL` (`:39-41`, persisted), `reportSettings` (`:38`, **not** persisted on iOS).
- `TransferPlanPresentation`, `PhotographerJobSetupPresentation`, `PhotographerJobViewModel.startPresentation` (`:467`), and `SafetyValidator`.

**Mac:**
- `BitMatch/Views/CopyAndVerify/CopyAndVerifyView.swift`: its own `readinessIssues`/`readinessWarnings` (`:28-80`) feed `TransferPlanPresentation` (`:12-24`).
- `TransferPlanView.swift:4-204` (locations, Quick/Project control, project setup, preflight card, option summary, `TransferOptionsView` at `:264-298`, action area `:160-202`).
- `HorizontalFlowView.swift` (pickers, drag-and-drop, drop validation `:461-517`).
- `CameraLabelView.swift`, `PhotographerJobSetupView.swift`, `RemoteBackupDestinationView.swift`.
- The start guard `AppCoordinator.copyAndVerifyPreflightIsReady` (`AppCoordinator.swift:107-136`).
- The time estimate `AppCoordinator.updateTimeEstimate` (`:405-425`).

**iPad/iPhone:**
- `BitMatch-iPad/Views/CopyAndVerifyView.swift` (1,518 lines): the plan is built from `operationReadinessAssessment` with a string-filter hack (`:15-36`).
- Also in that file: `MobileTransferWorkflowPicker` (`:190`), `MobileProjectSetupCard` (`:249-450`), `EnhancedSourceDestinationView` (`:555`), `DestinationsFlowView` (`:729`), `CollapsibleVerificationSection` (`:1148`), `StartTransferButtonView` (`:1295-1393`), `ReportToggleCard` (`:1484`).
- Dead code: `IpadTransferPlanOptionSummary` (`:526`) and `EnhancedDestinationCard` (`:820`) have no callers, and `ReadinessBannerView` (`:1395`) is disabled at `:105`.

### 4.2 Behaviour differences

1. **Three readiness checks, and none matches the runtime check.**

   | Rule | Mac view (`CopyAndVerifyView.swift:28-80`) | Mac start guard (`AppCoordinator.swift:107-136`) | Shared / iOS (`SharedAppCoordinator.swift:1009-1078`) | Runtime (`SafetyValidator.swift:113-133`) |
   |---|---|---|---|---|
   | Still analysing source | blocks (via `isAnalyzing`) | blocks | not in assessment; iPad view adds it (`iPad CopyAndVerifyView.swift:32`) | — |
   | Free space | block if `available < source + 100 MB`; skipped for a destination with a safety issue (`else if`) | same | block if `source/available > 0.9`, warn > 0.7, **only once that destination's folder info has loaded** | throws unless `available > source + 1 GB` |
   | Messages | own strings | none (silent `return`) | own strings | error alert |

   Both preflights can say *Ready* and then the run fails at start. For example, 500 MB of headroom on the Mac, or a 1 GB source with 1.5 GB free on iOS (ratio 0.67). Promise 1 wants this closed.

   Also:
   - Mac `canStartOperation` is only `sourceURL != nil && !destinationURLs.isEmpty` (`FileSelectionViewModel.swift:432-434`).
   - Shared `startOperation()` checks only that the locations exist (`:358-370`); only `startProjectOperation` checks readiness (`:529`).
   - Destination writability is checked only at runtime (`SafetyValidator.swift:86`).
   - `sourceIsWriteProtected` is computed (`FileSelectionViewModel.swift:585-586`) but never read.
2. **Explaining a disabled Start.**
   - The Mac keeps the button title and puts the reason below it (`TransferPlanView.swift:188-192`).
   - iPad changes the button text to the reason and uses a warning icon (`CopyAndVerifyView.swift:1316-1328`). It also adds "Ready to copy N files (size) to N destinations" (`:1338-1346`), which the Mac lacks.
3. **Project gating.** On iPad, selecting the Project workflow is enough to require `projectStartPresentation.canStart` (`:1310-1313`). On the Mac only a *prepared* card gates start (`TransferPlanView.swift:161-169`, `AppCoordinator.swift:70-78`), so the Mac with Project selected but unprepared starts a plain transfer.
4. **Adding destinations.**
   - The Mac validates on add: folders only, duplicates by resolved path, and conflict with the source. It shows a toast on rejection (`HorizontalFlowView.swift:461-505`, `ContentView.swift:519`). It auto-adds detected backup drives unless the user dismissed them, and auto-removes ejected ones.
   - iOS `addDestinationFolder` dedups only by exact URL equality (`SharedAppCoordinator.swift:233-240`), so problems surface later in the preflight card. iOS has no drag-and-drop and no drive detection (an iOS platform limit for detection).
5. **Camera label.**
   - The Mac uses `detectCameraWithMemory` (fingerprints, remembered labels) and persists `destLabelSettings`.
   - iOS sets `label = camera.name` only when confidence > 0.8 and the label is empty (`SharedAppCoordinator.swift:647-662`), and persists nothing.
   - **R5** resolves this.
6. **Time estimate.**
   - The Mac benchmarks drives and shows "Estimated time …" above Start (`TransferPlanView.swift:171-177`).
   - iOS shows only a per-mode estimate inside Advanced → Verification (`CopyAndVerifyView.swift:1270-1274`).
   - **R3** moves the Mac estimate into a model, but that model is Mac-only.
7. **Persistence.** The Mac persists report prefs and camera label, and iOS persists neither (**R4**, **R5**). The Mac saves last destinations but never restores them: `restoreLastDestinations()` has no caller (`FileSelectionViewModel.swift:418`).
8. **Project setup.** The Mac has a preset picker and "Save as preset" (`PhotographerJobSetupView.swift:180-215`). iPad has layer toggles only.
9. **SFTP.** It is Mac-only by design. iOS stores profile metadata and says "Uploads remain a Mac task" (`ModularContentView.swift:1143`). Keep that as the explicit exception.
10. **Advanced options.** Both platforms already have an Advanced disclosure, but they differ in detail (§6).

### 4.3 Proposed shared component: `SetupScreen`

**Readiness model, the first thing to build (`Shared/Core/Models/TransferReadiness.swift`):**

```swift
struct TransferReadiness: Equatable, Sendable {
    enum Status: Equatable, Sendable { case needsSource, needsDestination, analysing, blocked, ready }
    let status: Status
    let blockers: [String]      // one wording, used by every platform
    let warnings: [String]      // Quick mode; limited space (> 70 % of free space)
    static func assess(source: URL?, sourceBytes: Int64?, isAnalysingSource: Bool,
                       destinations: [URL], settings: CameraLabelSettings,
                       verificationMode: VerificationMode,
                       availableBytes: (URL) -> Int64?,       // injected; no dependency on folder-info caches
                       isWritable: (URL) -> Bool) -> Self
    static let requiredHeadroomBytes: Int64 = 1_000_000_000   // the runtime rule, shared with SafetyValidator
}
```

- It merges the Mac view rules, the Mac guard rules and the shared rules into one set. The analysing gate moves into the model instead of the view.
- **Space:** block below `sourceBytes + requiredHeadroomBytes`, which is the same constant `SafetyValidator.validateAvailableSpace` uses, so *Ready* can no longer fail at start. Warn above 70% of free space. Check every destination whose capacity is readable, not only those with loaded folder info. Check space even when another issue exists (drop the `else if`).
- **New:** a destination that isn't writable blocks start.
- `TransferPlanPresentation.make` takes a `TransferReadiness` directly. That deletes the iPad string-filter hack (`iPad CopyAndVerifyView.swift:18-24`) and the Mac `readinessIssues`.
- Later, in a one-line change after S2 and R6, `SharedAppCoordinator.operationReadinessAssessment`, `canStartOperation` and `startOperation()` delegate to it. This is the same merge R6 describes, and R6 should consume this type rather than write a second one.

**Destination selection policy (`Shared/Core/Models/DestinationSelectionPolicy.swift`):** the add-time rules from `HorizontalFlowView.swift:461-517` (folders only, resolved-path duplicates, source conflict). It returns `.accept` or `.reject(reason)`. The iOS adapter uses it before calling `addDestinationFolder`, so iOS rejects bad picks the way the Mac does.

**Start presentation:** one `StartButtonPresentation` combining `TransferReadiness`, the project gate and the in-progress state. It returns the button title, enabled state, blocker line and "Ready to copy N files (size) to N backups" line. Both platforms render the same thing.

**Screen inputs:**
- `SetupPresentation`: plan, readiness, start button, workflow (Quick/Project), label, options summary, estimate text.
- `SetupActions`: pick/drop source, add/drop/remove destination, start, choose workflow.
- Bindings for the Advanced options (§6).
- Two platform slots:
  - `sourceAccessory`: the Mac shows detected cards and drive speed; iOS shows nothing.
  - `projectRemoteBackup`: the Mac `RemoteBackupDestinationView`; the iOS profile picker plus "Uploads run on a Mac".

**Layout:**
- `.compact`: source card, backups list, workflow control, preflight card, one-line summary, Advanced disclosure, Start (full width, ≥44 pt).
- `.toolbar`: source and backups side by side (as in `EnhancedSourceDestinationView` at regular width), everything else below.
- `.sidebar`: source → backups flow across the top (the Mac `HorizontalFlowView` idea), with project setup and preflight in a trailing column.

### 4.4 Decisions for Mike

- **S-1.** Should Setup block below source + 1 GB free (matching the runtime) or keep a smaller preflight margin and change the runtime to match? Recommended: one number, 1 GB, everywhere.
- **S-2.** Project gating: should choosing Project gate Start (iPad) or only a prepared card (Mac)? Recommended: the iPad rule, because choosing Project and getting a plain transfer is surprising.
- **S-3.** Should the Mac restore last-used backups at launch (the code exists but is unwired)? Recommended: only when all of them are still mounted.

---

## 5. History

"History" is two unrelated features.

### 5.1 Implementations

**A. Transfers library: already shared.**
- `Shared/Views/TransferLibraryView.swift` (Queue/History picker `:31-34`, record rows `:87-148`, `ReauthorizeLocationsView` `:166`, `AddQueuedTransferView` `:306`, `TransferHistoryDocument` `:405`) over `LocalTransferJournal.swift`.
- It is presented as a sheet from:
  - Mac: `ContentView.swift:84-87`, clock button `:225-230`.
  - iPad: `ModularContentView.swift:47-49`, button `:115`.
  - iPhone: `PhoneContentView.swift:48-52,61-63`.
- An "interrupted" banner is copied into all three (`ContentView.swift:154-157`, `ModularContentView.swift:77-80`, `PhoneContentView.swift:23-26`).

**B. Master Report: written twice.**
- Mac: `BitMatch/Views/MasterReportView.swift` plus `MasterReport/Components/*`, with the scanner `BitMatch/Core/Services/DriveScanner.swift`.
- iOS: `ModularContentView.swift:486-1042` (`MasterReportView`, header, empty, scanning, list, `TransferSelectionCard`, `VolumeSelectionSheet`, `ReportConfigurationSheet`), with the scanner `Platforms/iOS/Services/IOSDriverScanner.swift`.

### 5.2 Behaviour differences

1. **iOS probably never finds real reports.**
   - The exporter writes `BitMatch_Report_<date>.json` (`ReportExporter.swift:439,485`).
   - iOS matches only `BitMatchReport.json` or names ending in `_Report.json` (`IOSDriverScanner.swift:137`).
   - The Mac matches `bitmatch_report_*.json` (`DriveScanner.swift:182-193`).
   - iOS also opens volume paths with `URL(fileURLWithPath:)` and never starts security-scoped access. The picker-based `selectDriveAndScan` that does start access (`IOSDriverScanner.swift:13-35`) is unused.
2. **Scan window and limits.** The Mac scans today only (`DriveScanner.swift:41-44`) and skips reports over 20 MB. iOS scans the last 2 days (`IOSDriverScanner.swift:108,142-143`), skips reports of 10 MB or more, and stops after 50,000 files.
3. **What "verified" means.**
   - The Mac uses `issues == 0` (`DriveScanner.swift:79`), so a Quick copy with no checksums reads as verified. That is a false green (promise 2).
   - iOS uses `matches > 0 && issues == 0` (`IOSDriverScanner.swift:249`), and hard-codes `verificationMode: .standard` (`:296`).
4. **Report metadata.**
   - The Mac takes production, client and company from `settingsViewModel.prefs`, and maps **`technician` from `prefs.notes`** (`MasterReportView.swift:111-123`), which is a mapping bug.
   - iOS starts from an empty `ReportConfiguration.default()` and uses per-session fields (`ModularContentView.swift:495,1008-1022`). It never reads `reportSettings`.
5. **Output.** The Mac uses `NSSavePanel` and writes the PDF plus a sibling JSON. iOS uses a temp folder and a share sheet (`ModularContentView.swift:614-667`), and shows the "Report Generated" alert on top of the share sheet (`:669-672`). The Mac shows its success alert even after a failure (`MasterReportView.swift:86-99,138-143`). `saveMasterReportJSON` is an empty stub (`:146-149`).
6. **Grouping.** The Mac groups cards by camera with per-camera select-all and totals (`MasterReportTransfersView`, `CameraGroupView`). iOS shows a flat list with an "x/y selected" count.
7. **Library status.** Only `.completed` is green. Interrupted, cancelled and issues all show as plain grey (`TransferLibraryView.swift:92-93`). The launch banner covers `.interrupted` only.
8. **Replay side effect.** Queue replay sets `reportSettings = record.reportSettings` (`SharedAppCoordinator.swift:335-341`). On iOS those values then stick for later manual transfers. The Mac re-pushes its prefs on the sheet's `onAppear` (`ContentView.swift:86`) and at start (`AppCoordinator.swift:90`).
9. **Reaching Master Report.** iPad offers it only when idle. iPhone offers it at any time, including mid-transfer (§1.2.6).

### 5.3 Proposed shared components

**A. `TransferLibraryView` stays.** Add `TransferLibraryPresentation` (`Shared/Core/Models/`) for:
- the per-record state label and tone (completed = verified; issues/interrupted = needs attention, orange; cancelled = neutral; failed = red);
- the actions each record allows (`TransferLibraryView.swift:101-125`);
- search/filter (`:18-25`).

Also add one `needsAttentionCount` that all three banners read, instead of three copies of the `.interrupted` filter. Move `TransferHistoryDocument` out of the view file into `Shared/Core/Services/`.

**B. `MasterReportScreen`**, built on:
- One `Shared/Core/Services/ReportScanner.swift`: one filename rule (a superset of both, including `BitMatch_Report_*.json`), one size limit, one date window, and security-scoped access around the scan on iOS. "Verified" means `issues == 0 && verificationMode != .quick && matches > 0`, with the mode read from the report.
- `MasterReportModel` (`@MainActor ObservableObject`): found cards, per-camera grouping and totals (from `MasterReportTransfersView`/`CameraGroupView`), selection, the scan task with a stale-scan token (both platforms already have one), and generation.
- `ReportConfiguration.make(from: ReportPrefs, productionNotes:)`, with the technician mapping fixed.
- **Actions:** `chooseLocation` (Mac: `NSOpenPanel`; iOS: document picker with security scope), `scan`, `toggle(card)`, `toggleCamera(name)`, `generate` (Mac: save panel; iOS: share sheet; each shows success only after the write succeeds).

**Layout:**
- `.compact`: location, scan, totals as a 2×2 grid, and camera groups as collapsible sections.
- `.toolbar`: totals in one row.
- `.sidebar`: camera groups in a leading list and selected cards in the trailing detail.
- Remove the nested 300 pt `ScrollView` (`ModularContentView.swift:777-795`).

### 5.4 Decisions for Mike

- **H-1.** Should the Master Report date window be today only (Mac) or the last N days (iOS: 2)? Recommended: a date picker defaulting to today.
- **H-2.** Should Master Report later be built from the journal instead of scanning drives? That would work on iOS without volume access and would include cancelled or interrupted runs. Out of scope here; a candidate follow-up.

---

## 6. P4: verification mode, ASC MHL and report toggles under Advanced

**Current state.** The thesis finding ("the Mac setup screen shows verification mode and the ASC MHL and report toggles at the top level") is **mostly already fixed on `main` for Setup**:
- The Mac `TransferOptionsView` is an "Advanced" `DisclosureGroup`. It is collapsed by default (`ContentView.swift:22`) and holds the camera label, verification picker, ASC MHL toggle and report toggle (`TransferPlanView.swift:264-298`).
- iPad has the same structure (`BitMatch-iPad/Views/CopyAndVerifyView.swift:65-99`).

What still violates P4, or differs:

1. **Compare shows the verification mode at the top level on both platforms:**
   - Mac: an expandable radio list with MHL badges (`CompareFoldersView.swift:143-247`).
   - iOS: a `.menu` picker (`ModularContentView.swift:385-390`).
2. **The Advanced label advertises the options.** Its trailing text is "`<mode>` · Reports on/off" (Mac `TransferPlanView.swift:292`, iPad `CopyAndVerifyView.swift:86`). The one-line summary above Advanced repeats the mode (Mac `:86-92`, iPad `:59-62`). Recommended: keep the one-line summary, because it tells people whether the copy is verified (promise 2). Make the disclosure label plain "Advanced", and show a trailing note only when something is *non-default*, e.g. "Quick mode" or "Reports off".
3. **iPad nests a second disclosure inside Advanced for verification** (`CollapsibleVerificationSection`, `:1148`), and each row shows an "MHL" badge (`:1250-1260`) that is easy to confuse with the ASC MHL toggle. Flatten this to one picker, as on the Mac, and drop the badge.
4. **Labels disagree.**
   - Setup: "Create PDF & CSV Report" (Mac) and "Create PDF & CSV reports" (iPad `ReportToggleCard`, `:1498`).
   - Settings: iOS says "Generate PDF & JSON reports" (`ModularContentView.swift:1079`), and Mac Preferences says "Generate PDF & CSV reports automatically" (`PreferencesWindow.swift:163`).
   - iOS writes no PDF.
   - Use one label from `TransferOutcomePresentation.reportFormatsDescription` (§2.3).
5. **Settings disagree.** iOS Settings has the ASC MHL toggle under "Advanced verification" (`ModularContentView.swift:1061-1075`), but Mac Preferences has no ASC MHL control (`PreferencesWindow.swift:106-124`). Either add it to Mac Preferences' "Advanced verification" or remove it from iOS Settings. Recommended: add it on the Mac, because one app should have one set of settings.

**Shared component: `TransferOptionsSection`** (`Shared/Views/Setup/TransferOptionsSection.swift`). This is used by `SetupScreen` and, with the label and report rows hidden, by `CompareScreen`.

- **Inputs:**
  - `Binding<VerificationMode>`
  - `Binding<Bool>` for ASC MHL
  - `Binding<Bool>` for reports
  - `Binding<CameraLabelSettings>?` (nil on Compare)
  - `isExpanded: Binding<Bool>`
  - `reportFormatsDescription`
  - `estimateText: String?`
- **Behaviour:**
  - ASC MHL is disabled in Quick mode and explains why ("Quick mode records sizes only, so there is no checksum to hand off").
  - Changing the mode persists through the existing shared sink (`SharedAppCoordinator.swift:206-211`); nothing calls `saveVerificationMode` from a view.
- **Layout:** a single flat `DisclosureGroup` on all widths. At `.sidebar` width the rows sit in two columns (label | verification and records).

The Mac can adopt it before R4, because the Mac adapter passes `$coordinator.settingsViewModel.prefs.makeReport` as the report binding.

---

## 7. Work order

Each step ships on its own: it builds both schemes, passes both test suites, and leaves the app usable. The order is Compare first, then the pieces with no dependency on step 3, then the ones that need it.

### Step 4.0: Groundwork (no locked files)

- [ ] Move `AdaptiveWorkbenchLayout`, `ResultTableLayoutPolicy`, `MasterReportLayoutPolicy` and `TransferCardLayoutPolicy` from `BitMatch/Views/…` to `Shared/Core/Models/` with `git mv`. They import only CoreGraphics. Existing tests (`AdaptiveWorkbenchLayoutTests`, `ResultTableLayoutPolicyTests`, `MasterReportLayoutPolicyTests`, `TransferCardLayoutPolicyTests`) keep passing unchanged.
- [ ] Add `Shared/Views/Style/BitMatchStyle.swift` and move `Color(hex:)` there from `BitMatch-iPad/ContentView.swift:5-29`. `Shared/Core/Services/SharedReportGenerationService.swift:622,648` already declares `init(hex:)` on `NSColor`/`UIColor`. That is a different type, so there is no clash, but run `rg -n "init\(hex" BitMatch Shared BitMatch-iPad` first to confirm nothing else declares it on `Color`.
- [ ] Add `Shared/Core/Models/MainScreen.swift`: `enum MainScreen { case setup, running, outcome }` with `static func resolve(mode:operationState:isOperationInProgress:)`. It replaces the three routing switches (Mac `ContentView.swift:177-203`, iPad `ModularContentView.swift:82-100`, iPhone `PhoneContentView.swift:30-80`), and is mode-aware, so Compare never routes to the transfer outcome. Wire it into the three shells in this step. It is pure, so `SharedAppCoordinator.showsOutcomeSummary` stays untouched.
  - Test `MainScreenTests.compareOutcomeIsNotTransferOutcome`: mode `.compareFolders`, state `.completed` → a compare screen, not the transfer outcome. **Plant:** in `resolve`, drop the `mode` check so any `.completed` state returns `.outcome`.
  - Test `MainScreenTests.pausedStaysRunning`. **Plant:** map `.paused` to `.setup`.

### Step 4.1: Compare readiness and outcome model (no locked files)

- [ ] Add `ComparePresentation`, `CompareReadiness` and `CompareOutcome` (§1.3), with a same/nested check through `SafetyValidator.destinationSafetyIssue`.
- [ ] Mac `CompareFoldersView` and iOS `ComparisonControlsView` both read `presentation.readiness`. The iOS button now exists with a disabled state and a reason line. Mac ⌘R checks readiness before calling start (`ContentView.swift:505-509`).
- [ ] Tests in `BitMatchTests/ComparePresentationTests.swift`:
  - `sameFolderIsBlocked`. **Plant:** remove the `destinationSafetyIssue` call from `ComparePresentation.make`.
  - `nestedFolderIsBlocked`. **Plant:** same as above.
  - `loadingBlocksCompare`. **Plant:** drop `isLoading` from the readiness `guard`.
  - `runningBlocksCompare`. **Plant:** drop `isRunning` from the readiness `guard`.
  - `cancelledOutcomeIsNotMatch`, for a cancelled compare with stale clean stats. **Plant:** return `.match(stats)` whenever `stats?.isClean == true`, before checking state.
- [ ] Manual check on iPhone width: both buttons stay disabled until both folders are loaded.

### Step 4.2: `CompareScreen` (no locked files; iOS mode-switch lock is C-2)

- [ ] Add `Shared/Views/Compare/CompareScreen.swift`: folder slots, the `TransferOptionsSection` subset (§6), inline progress, and the existing `CompareResultsView` for the outcome, with "Compare again".
- [ ] Add adapters:
  - Mac: `BitMatch/Views/CompareFoldersView.swift` becomes about 60 lines that build the presentation from `AppCoordinator`. Picking writes `fileSelectionViewModel.leftURL`, which already syncs to shared through S1/S2.
  - iOS: `ModularContentView.CompareFoldersView` becomes an adapter from `SharedAppCoordinator`.
- [ ] Delete from `ModularContentView.swift`: `CompareFoldersHeaderView`, `FolderSelectionCard`, `ComparisonControlsView` and `ComparisonProgressView` (`:239-480`).
- [ ] Delete from `CompareFoldersView.swift`: the Mac-only card, mode list and action code.
- [ ] Mac: while comparing, `resultsArea` no longer shows `ResultsTableView`.
- [ ] Cancel toast wording from `MainScreen` + mode: "Compare cancelled" vs "Transfer cancelled".
- [ ] Check at 390, 700 and 1,100 pt on iOS simulators and at 580 and 1,200 pt on the Mac. Use keyboard only on the Mac.

**Status of 4.1 and 4.2 (branch `cloud/compare-screen`, not compiled):** implemented, with these differences from the text above:
- 4.0 is not done. Instead of `MainScreen`, each shell routes Compare mode to its mode view, and `SharedAppCoordinator.lastOperationWasCompare` keeps a finished compare out of the transfer outcome (`showsOutcomeSummary`, Mac `mainContentSwitch`). `BitMatchStyle` was not needed: the screen uses system styles.
- 4.6 is not done, so Compare has its own "Advanced" disclosure (one `Picker`) instead of `TransferOptionsSection`.
- How a compare ended is `SharedAppCoordinator.lastCompareEnd` (`CompareRunEnd`), not the shared `operationState`, which transfers also write.
- A folder whose details could not be read does not block Compare (iOS picks can fail that scan); it shows "Folder details unavailable". Only still-loading details block.
- The checks per mode are `CompareCheckPlan`, used by both `ComparisonCoordinator` and the screen. Paranoid is byte-by-byte plus SHA-256 independent of `VerificationMode.checksumTypes`.
- The mode switcher lock is `ModeSwitchPolicy` (running operation or running queue). iOS switchers call `switchMode(to:)` and are disabled; the Mac hides its selector as before and guards ⌘1–3.
- Tests are in `BitMatchTests/ComparePresentationTests.swift` and `BitMatchTests/SharedCompareFlowTests.swift`, each with its **Plant:** line.
- Still to do by someone with Xcode: build both schemes, run both suites, plant each bug, and check 390/700/1,100 pt on iOS and 580/1,200 pt on the Mac.

### Step 4.3: Completion guidance fix (no locked files; ships alone, before anything else in Completion)

- [ ] `CompletionSummaryView.swift:281`: replace `CompletionVerdictPresentation.make(verdict).sourceGuidance` with the state-aware `make(state:rows:hasErrors:hasCriticalErrors:)`'s `sourceGuidance`, which the header already computes (`:84-91`). Hide `ErrorDetailsView` when the state is `.cancelled` (`:63-69`).
- [ ] Test `BitMatch-iPadTests/CompletionGuidanceTests.swift` `cancelledGuidanceIsNotFailedFileGuidance`. To make it testable, move the guidance choice into a tiny `static func guidance(for:)` on the view file's presentation helper. **Plant:** change `guidance(for:)` back to `CompletionVerdictPresentation.make(verdict).sourceGuidance`.

### Step 4.4: History scanner and library presentation (no locked files)

Written on branch `cloud/history-screen` without Xcode: reviewed, not compiled or run. The banner counts interrupted transfers only, because a run with issues already showed its verdict and stays in the queue. `LocalTransferState` has no failed state, so no library label is red. Moving `TransferHistoryDocument` out of the view file (§5.3 A) is left for 4.10.

- [x] Add `Shared/Core/Services/ReportScanner.swift` (§5.3 B). The Mac `DriveScanner` and iOS `IOSDriverScanner.scanForBitMatchReports` both call it; their volume-listing code stays platform-specific.
- [x] Tests (`BitMatchTests/ReportScannerTests.swift`, real temp folders written by `ReportExporter`'s JSON encoder):
  - `findsExporterFilenames`. **Plant:** restore the iOS rule `filename == "BitMatchReport.json" || filename.hasSuffix("_Report.json")`.
  - `quickModeReportIsNotVerified`. **Plant:** `let verified = report.statistics.issues == 0`.
- [x] Fix the Mac `technician` mapping and the success-after-failure alert (`MasterReportView.swift:86-99,111-123`).
  - Test `ReportConfigurationTests.technicianIsNotNotes`. **Plant:** `technician: prefs.notes`.
- [x] Add `TransferLibraryPresentation` and `needsAttentionCount`, and use them in `TransferLibraryView` and the three banners.
  - Test `interruptedIsNotGreen`. **Plant:** map `.interrupted` to the `.verified` tone.

### Step 4.5: One readiness rule for Setup (touches views only; coordinator delegation waits for S2 and R6)

- [ ] Add `TransferReadiness` (§4.3) and `DestinationSelectionPolicy`. `TransferPlanPresentation.make` gains an overload that takes a `TransferReadiness`.
- [ ] Mac `CopyAndVerifyView.readinessIssues/Warnings` (`:28-80`) and iPad `CopyAndVerifyView.plan` (`:15-36`) both call `TransferReadiness.assess`.
- [ ] iOS `DestinationsFlowView`'s add path runs `DestinationSelectionPolicy` before `addDestinationFolder` and shows the rejection reason.
- [ ] Interim state: `AppCoordinator.copyAndVerifyPreflightIsReady` (locked) still uses the 100 MB rule. The new view rule is stricter, so the view never offers Start when the guard would refuse. The reverse (the guard refusing silently when the view allows Start) cannot happen, because 1 GB > 100 MB. R6 deletes the guard.
- [ ] Tests (`BitMatchTests/TransferReadinessTests.swift`, capacity and writability injected):
  - `headroomMatchesRuntime`: 1 GB source with 1.5 GB free is blocked. **Plant:** `requiredHeadroomBytes = 100 * 1024 * 1024`.
  - `analysingBlocks`. **Plant:** remove the `isAnalysingSource` branch.
  - `spaceCheckedWithoutDestinationFolderInfo`: the source size is known, a destination's capacity is readable through `availableBytes`, and no destination folder info exists → a short destination is still blocked. **Plant:** skip the space rule unless a `destinationInfo` value is also passed, as `SharedAppCoordinator.swift:1057` does today.
  - `unwritableDestinationBlocks`. **Plant:** drop the `isWritable` check.
  - `spaceCheckedAlongsideSafetyIssue`: a destination inside the source *and* short of space reports both. **Plant:** turn the space check back into `else if`.
  - `parityWithRuntime`: for a table of (source, free) pairs, `assess(...).status == .ready` iff `SafetyValidator.checkedRequiredSpace` passes. **Plant:** change `requiredHeadroomBytes` to `999_000_000`.
- [ ] After S2 and R6 (separate commit): `SharedAppCoordinator.operationReadinessAssessment` returns the `TransferReadiness` result, `canStartOperation`'s copy branch uses it, and `startOperation()` refuses and reports when it is not ready.

**Status of 4.5 (branch `cloud/shared-selection-boxes`, not compiled):** implemented, together with the shared source and backup boxes, with these differences from the text above:
- The merged rule already existed as `OperationReadinessAssessment.assess`. Its body moved into `TransferReadiness.assess` (`Shared/Core/Models/TransferReadiness.swift`), which adds the writability rule (a backup that exists but is not writable blocks; one the app cannot see is left to the copy) and checks space even for a backup with another finding. `OperationReadinessAssessment` is now a view of it, so `canStartOperation` (and through it `startCurrentMode`), `startProjectOperation` and the Setup screen already use the one rule; `startOperation()` itself still checks only that the locations exist. `SharedAppCoordinator.transferReadiness` supplies free space and `TransferReadiness.isWritableFolder`.
- `DestinationSelectionPolicy` (`Shared/Core/Models/`) has the Mac drop rules for backups and the source. The macOS system-folder check is Mac-only, because every iOS Files location lives under `/private/var/mobile`.
- The boxes: `SetupLocationsView` (view over `SetupLocationsPresentation`) and one adapter, `CoordinatorSetupLocations`, whose `SetupLocationSelection` runs the policy and then the platform's add. The Mac passes `MacSetupLocations` (open panel, drag and drop, the toast); iOS passes `IOSSetupLocations` (Files picker, an alert). `HorizontalFlowView`, `AdaptiveWorkbenchLayout`, `EnhancedSourceDestinationView`, `ProfessionalSourceCard`, `DestinationsFlowView`, `CompactDestinationCard` and `SharedAppCoordinator.addDestinationFolder` are deleted.
- Tests: `TransferReadinessTests`, `DestinationSelectionPolicyTests`, `SetupLocationsPresentationTests`, each with its **Plant:** line. `spaceCheckedWithoutDestinationFolderInfo` is covered by the existing `ReadinessRuleTests.smallHeadroomIsBlockedWithoutAnyFolderInfo`.

### Step 4.6: Shared Advanced options, and the rest of P4 (no locked files)

- [x] Add `TransferOptionsSection` (§6). Mac `TransferOptionsView` (`TransferPlanView.swift:264-298`) and the iPad Advanced block (`CopyAndVerifyView.swift:65-99`) both use it. Delete `CollapsibleVerificationSection`, `VerificationModeRow` and `ReportToggleCard` once they are unused.
- [x] The Advanced label shows only non-default settings. One report label comes from `reportFormatsDescription`, in Setup, iOS Settings and Mac Preferences.
- [x] Add the ASC MHL toggle to Mac Preferences → "Advanced verification" (`PreferencesWindow.swift:106-124`) (§6.5).
- [ ] Compare uses the section with only the verification picker (already done in 4.2 if 4.6 lands first; otherwise 4.2 uses a temporary private disclosure).
- [x] Tests (`BitMatchTests/TransferOptionsPresentationTests.swift`):
  - `advancedLabelHidesDefaults`: Standard mode, reports on → empty trailing note. **Plant:** always return `"\(mode.rawValue) · Reports on"`.
  - `ascMHLUnavailableInQuick`. **Plant:** make `ascMHLEnabled` return `true` for every mode.
  - `iOSReportLabelDoesNotPromisePDF` (iOS test target). **Plant:** return `"PDF & CSV"` unconditionally.

- Done on branch `cloud/advanced-options` (not compiled; no Xcode). Differences from §6: the camera label is a platform slot (`labelContent`) rather than a `Binding<CameraLabelSettings>`, because `CameraLabelView` (Mac) and `CollapsibleLabelingSection` (iOS) are target-specific; `estimateText` is only passed on iOS (the Mac keeps its drive-benchmark estimate above Start); a set camera label also appears in the Advanced note. Compare adoption is left to the Compare branch: `TransferOptionsSection(isExpanded:verificationMode:)` is the picker-only form.

### Step 4.7: `OutcomeScreen` (after S2)

- [ ] Add `TransferOutcomePresentation` (§2.3) over whatever verdict S2 produces, and `OutcomeScreen`. Move `CompletionEvidencePresentation` to Shared.
- [ ] Add adapters:
  - Mac: `ContentView.completionView` + `ResultsTableView` banner.
  - iOS: `CompletionSummaryView` becomes an adapter.
- [ ] Surface the report location: `ReportExporter.autoSaveReports` already returns or knows its URLs. The executor passes them on through whatever S2's completion path is. **This needs one small change in `CopyVerifyExecutor` after the lock lifts.**
- [ ] Decide O-1 and O-2 first.
- [ ] Tests:
  - `cancelledToneIsCancelled`, on both platforms through the same function. **Plant:** derive tone from `presentation.symbol`, as `ResultsTableView.swift:518` does.
  - `bytesAreVerifiedNotSourceSize`. **Plant:** `bytesVerified = sourceFolderInfo.totalSize`.
  - `durationSaysStoppedWhenCancelled`. **Plant:** always use "Completed in".
  - Extend `PlatformVerdictParityTests` so one fixture gives identical `TransferOutcomePresentation` values whether it is built through the Mac adapter or the iOS adapter. **Plant:** in the Mac adapter, pass `hasErrors: false`.

**Status of 4.7 (branch `cloud/outcome-screen`, not compiled):** implemented, with these differences from the text above:
- O-1 and O-2 follow the thesis decisions: `SharedAppCoordinator.startNewTransfer()` clears the source and keeps the backups, and Retry and Export are on the shared screen, so the Mac has them.
- There is one adapter, not two: `CoordinatorOutcomeScreen` (`Shared/Views/Outcome/`) builds `TransferOutcomePresentation.make(coordinator:)` for every platform. The Mac `completionView` passes its project dashboard as a slot; iOS `CompletionSummaryView` is a 10-line wrapper, so `ModularContentView` and `PhoneContentView` are unchanged. The parity test therefore compares the two engines' outcomes rather than two adapters.
- Retry, Export and the duration come from the transfer's journal record (`SharedAppCoordinator.outcomeRecord`); the timing service clears its timing on completion, so the old "Completed in" line never appeared.
- The report location is **not** surfaced yet: it needs `ReportExporter.export` to return its URLs through `CopyVerifyExecutor`. `reportLocation` and `reportFormatsDescription` are left out of the model until then.
- "Not reached" counts are left out: the outcome has no reliable total of planned files.
- A cancelled outcome is grey (`.secondary`), matching Compare and Transfers; it was red on the Mac and orange on iOS.
- The Mac `ResultsTableView` now shows only live results while a transfer runs; its completion banner, backup summaries and symbol-derived tint are deleted.
- Tests: `BitMatchTests/TransferOutcomePresentationTests.swift`, `BitMatch-iPadTests/OutcomePresentationIOSTests.swift`, and an extension of `PlatformVerdictParityTests`, each with its **Plant:** line.

### Step 4.8: `SetupScreen` (after R4, R5, R6)

- [ ] Once selection, label and report settings live in `SharedAppCoordinator` (R4–R6), add `Shared/Views/Setup/SetupScreen.swift` with the `sourceAccessory` and `projectRemoteBackup` slots (§4.3).
- [ ] Mac adapter: `TransferPlanView` becomes the Mac slot provider.
- [ ] iPad: delete most of `BitMatch-iPad/Views/CopyAndVerifyView.swift`, including the dead `IpadTransferPlanOptionSummary`, `EnhancedDestinationCard` and `ReadinessBannerView`.
- [ ] One `StartButtonPresentation`. Decide S-2 first.
  - Test `projectSelectedButUnpreparedCannotStartPlain` (if S-2 is accepted). **Plant:** gate on `hasPreparedIngestAwaitingStart` only.
- [ ] Project presets: bring the Mac preset picker to iPad (`PhotographerJobSetupView.swift:180-215`) or remove it from the Mac. Recommended: share it.
- [ ] Check drag-and-drop on the Mac, and picking on iPhone and iPad with the Files app and an external drive (a physical device is needed for real removable media; the simulator only proves the picker flow).

**Status of 4.8 (branch `cloud/setup-screen`, not compiled):** implemented, with these differences from the text above:
- Same shape as 4.7: `SetupPresentation` and `StartButtonPresentation` (`Shared/Core/Models/SetupPresentation.swift`), `SetupScreen` and one adapter, `CoordinatorSetupScreen` (`Shared/Views/Setup/`). The Mac `MacSetupView` (was `TransferPlanView`) and iOS `CopyAndVerifyView` pass only slots, so no shell routing changed.
- The slots are `locations` (Mac `HorizontalFlowView` with drag and drop and drive discovery; iOS the Files-picker boxes), `problems` (Mac `UnreadableMediaBanner`), `projectSetup` (Mac `PhotographerJobSetupView` with presets and `RemoteBackupDestinationView`; iOS `MobileProjectSetupCard`), `labelContent` and `projectEvidence`. The source and backup boxes are therefore still two implementations; the shared screen owns the glow through `SetupLocationsContext.nextStep`.
- S-2 is decided and done: the Quick/Project choice is `SharedAppCoordinator.usesProjectWorkflow`, and `startCurrentMode()` starts nothing while Project is chosen without a prepared card, so ⌘R obeys it too. Start names the step ("Set up the card to start") and the project setup box glows.
- S-3 is decided and done: `MacVolumeAccessModel` restores last-used backups at launch only when all of them exist (`LastBackupsRestorePolicy`), before discovery can overwrite the saved list.
- Readiness is still the one rule on main (`operationReadinessAssessment`); `TransferReadiness` (§4.3) was not added. The estimate line sits above Start on every platform (Mac: drive benchmark; iOS: per-mode estimate).
- Presets are not shared yet: the Mac keeps its preset picker inside its project slot. `DestinationSelectionPolicy` (4.5) is not done.
- Deleted: `TransferPlanView`, `TransferPlanSourceCard`, `TransferPlanDestinationsCard`, `TransferPlanPreflightCard`, `TransferOptionsView` (Mac); `StartTransferButtonView`, `ReadinessBannerView`, `MobileTransferWorkflowPicker`, `IpadTransferPlanPreflightCard`, `IpadTransferPlanOptionSummary`, `EnhancedDestinationCard`, `CopyAndVerifyHeaderView`, `MobileWorkflowHeader` (iOS).
- Tests: `BitMatchTests/SetupPresentationTests.swift`, each with its **Plant:** line.

### Step 4.9: `ProgressScreen` (after S2 and R7)

- [ ] With `ProgressPresentationModel` in Shared (R7) and one operation state (S2), add `TransferProgressPresentation` and `ProgressScreen` (§3.3). Replace Mac `compactOperationView`/`TransferQueueView`/`CompactTransferCard` and iOS `OperationProgressView`.
- [ ] Delete the DEBUG fake queue items, `getFastLanePriority` and `generateDestinationProgress`.
- [ ] Stage comes from `progress.currentStage`.
- [ ] Add a `canCancel` guard, and disable ⌘. when nothing is running.
- [ ] Decide P-1 and P-2 first.
- [ ] Tests:
  - `runningCopyShowsBar`: state in progress, stage copying → the title is not "Preparing" and the fraction is > 0. **Plant:** map the in-progress state to `.preparing`, as `TransferQueueView.swift:273` does.
  - `resumeKeepsByteTotals`. **Plant:** call `reset()` on resume.
  - `speedExcludesPausedTime`. **Plant:** divide by wall-clock elapsed.
  - `cancelUnavailableWhenIdle`. **Plant:** `canCancel = true`.
  - `destinationRowsUseOwnCounts`: two destinations at different fractions. **Plant:** copy the overall fraction to every row.
- [ ] Check an iPad split view at 600 pt with 4 destinations: nothing is clipped.

**Status of 4.9 (branch `cloud/progress-screen`, not compiled):** implemented, with these differences from the text above:
- P-1 and P-2 follow the thesis decisions: Cancel asks for one confirmation (the button and Mac ⌘.), and the Mac's sleep assertion was already in `CopyVerifyExecutor`; the screen now says so.
- Shape as in 4.7: `TransferProgressPresentation` (`Shared/Core/Models/`, pure), `ProgressScreen` and one shared adapter `CoordinatorProgressScreen` (`Shared/Views/Progress/`). iOS `OperationProgressView` is a thin wrapper, so `PhoneContentView` is unchanged and `ModularContentView` only gains a `ScrollView`. The Mac shell routes a running copy to `MacTransferProgressView` (adds the project dashboard).
- Redraw scope: `SharedAppCoordinator.progress` is no longer `@Published`; it reads and writes `liveProgress` (`LiveProgressFeed`), which only `CoordinatorProgressScreen` and the two Compare adapters observe. The shells observe the coordinator and are not invalidated by a progress tick. Per-file `results` are still published by the coordinator (the Mac live results table needs them); that remains a per-file shell invalidation for a later step. **Done** on branch `cloud/results-perf` (not compiled): `results` is no longer `@Published`; it reads and writes `liveResults` (`LiveResultsFeed`), which only `ResultsTableView` and `CoordinatorOutcomeScreen` observe. A live per-file row goes through `receiveLiveResult(_:)` and does not touch the coordinator; whole-list writes (clear, reset, the engine's authoritative list) still announce themselves on it, so the verdict, outcome screen, journal and export read the same rows as before. Tests: `BitMatchTests/LiveResultsFeedTests.swift`.
- The fraction is the engine's `overallProgress` (not smoothed); speed is the shared EMA (`formattedAverageDataRate`) and time left `formattedTimeRemaining`, both excluding paused time (`notePaused`/`noteResumed`). Resume no longer resets the smoothing model.
- Destination rows report copy counts only (Waiting, Copying, Copied, Verifying); the engine has no per-backup verified count, so no row claims verification (audit C1).
- Not done here, because the Mac `CopyAndVerifyView` belongs to the 4.8 branch: its `compactOperationView` is now unreachable, and `BitMatch/Views/CompactTransfer/{TransferQueueView,CompactTransferCard,ContextualDestinationPopup,DestinationDetailView}` (with the DEBUG fake queue items, `getFastLanePriority` and `generateDestinationProgress`) are dead. Delete them once 4.8 has landed. **Done** on branch `cloud/dead-code-cleanup`: those files, `TransferCardLayoutPolicy` and its test, the fake-queue DEBUG helpers and menu item, and the uncalled `HorizontalFlowView.getFastLanePriority` are deleted.
- Tests: `BitMatchTests/TransferProgressPresentationTests.swift` (the five above plus `copiedBackupIsNotAVerdict`, `pausedOffersResumeWithoutSpeed`, `progressTicksDoNotRedrawTheShell`) and `BitMatch-iPadTests/ProgressPresentationIOSTests.swift`, each with its **Plant:** line. The opt-in workflow snapshots gain `mac-progress`, `mac-progress-wide`, `iphone-progress`, `narrowpad-progress` and `ipad-progress`.

### Step 4.10: `MasterReportScreen` (after R4 for shared `ReportPrefs`; the scanner is already done in 4.4)

Written on branch `cloud/master-report-screen` without Xcode: reviewed, not compiled or run.

- [x] Add `MasterReportModel` + `MasterReportScreen` (§5.3 B), with platform adapters for choosing a location and saving/sharing. Delete iOS `ModularContentView.swift:486-1042` and Mac `MasterReportView.swift` + `MasterReport/Components/*`, keeping any pieces that move into the shared screen.
  - `Shared/Core/Models/MasterReportPresentation.swift` (grouping, totals, button title and next step) and `MasterReportModel.swift` (folder, day, scan with a stale-scan token, selection, generation). `Shared/Views/MasterReport/MasterReportScreen.swift` draws them.
  - Adapters keep the name `MasterReportView(coordinator:)`, so no shell routing changed. Mac (`BitMatch/Views/MasterReportView.swift`): open panel, save panel writing the PDF and a sibling JSON, Show in Finder. iOS (`BitMatch-iPad/Views/MasterReportView.swift`): the Files document picker (`IOSDriverScanner.chooseFolder`, the only way iOS reads removable media) and the share sheet.
  - Success shows inline, and only after the save panel's write or a completed share. A cancelled save or share shows nothing; a failure shows an orange line. The Mac success alert and the iOS "Report Generated" alert on top of the share sheet are gone.
  - Production, client and company are edited under "Report details" and are the saved `ReportPrefs` (the same fields as Mac Preferences). Notes are per report. The iOS per-session technician field is gone, because `ReportConfiguration.make` leaves technician empty.
  - The skipped-reports notice and its scroll rule (`SkippedReportsPresentation.scrolls`) now apply on every platform, not only the Mac.
  - Layout: `.compact` and `.sidebar` show totals as a 2×2 grid, `.toolbar` in one row. `.sidebar` puts location, day, totals, details and the button in a leading column and the camera groups in a trailing one. No nested fixed-height list `ScrollView`.
  - `MasterReportLayoutPolicy` and its test are deleted; the screen uses `AdaptiveNavigationPolicy`. `IOSDriverScanner` keeps only the picker. `TransferHistoryDocument` moved to `Shared/Core/Services/` (left over from 4.4).
- [x] Decide H-1 first: a date picker defaulting to today (THESIS decisions). Changing the day scans the chosen folder again.
- [x] Tests (`BitMatchTests/MasterReportModelTests.swift`, scanner and renderer injected):
  - `groupsByCamera`. **Plant:** return one flat group.
  - `successOnlyAfterWrite`. **Plant:** replace `guard let delivery = try await deliver(...)` with `let delivery = (try? await deliver(...)) ?? .shared`.
  - `generateNeedsASelection`. **Plant:** delete the `selectedCount == 0` branch of `MasterReportPresentation.make`.
  - `noLocationNamesTheStep`. **Plant:** return `nextStep: nil` when there is no location.
  - `staleScanIsIgnored`. **Plant:** drop the `activeScanID == scanID` check in `MasterReportModel.scan`.
- [ ] Mac build and test run; check the screen at iPhone width, an iPad split view and a Mac window from 580 pt to wide; on a device, pick a USB drive or SD card in Files and scan it.

### Dependency summary

| Step | Locked files? | Needs |
|---|---|---|
| 4.0 Groundwork + `MainScreen` | no | — |
| 4.1 Compare readiness | no | — |
| 4.2 `CompareScreen` | no | 4.0, 4.1 |
| 4.3 Completion guidance fix | no | — |
| 4.4 Report scanner, library presentation | no | — |
| 4.5 `TransferReadiness` | views only; delegation commit touches `SharedAppCoordinator` | coordinator part: S2, R6 |
| 4.6 `TransferOptionsSection` (P4) | no | — |
| 4.7 `OutcomeScreen` | `CopyVerifyExecutor` (report URL) | S2 |
| 4.8 `SetupScreen` | — | R4, R5, R6, 4.5, 4.6 |
| 4.9 `ProgressScreen` | — | S2, R7 |
| 4.10 `MasterReportScreen` | — | R4, 4.4 |

After 4.10, and after R10, every Mac and iOS adapter is building the same presentation from the same `SharedAppCoordinator`. Merge each pair into one adapter in `Shared/Views/`, and delete `BitMatch/Views/{CompareFoldersView,CopyAndVerify/*,CompactTransfer/*,ResultsTableView,MasterReportView}` and `BitMatch-iPad/Views/{CopyAndVerifyView,OperationProgressView,CompletionSummaryView}` apart from their platform slots. Update `ARCHITECTURE.md` and mark thesis step 4 done.

---

## 8. Notes for step 2 and step 3 (found while planning, not part of step 4)

These belong to the Mac session's work, but they decide what the shared screens can show:

- The engine never sends `.copying`, so `operationState` stays `.inProgress` for the whole run (§3.2.1).
- `.resuming` is never cleared by the coordinator (`SharedAppCoordinator.swift:615`, `OperationStateService.swift:127-134`).
- Automatic pauses (background, low battery, sleep) mark the state paused without pausing the engine (`OperationStateService.swift:259-285`).
- The engine always sends `reusedCopies: nil`, so every "Reused N" label is dead.
- The report's `totalBytesProcessed` is `config.estimatedBytes`, which falls back to 1,000,000,000 when source info is missing (`CopyVerifyExecutor.swift:427`, `SharedAppCoordinator.swift:455`). That is not evidence (promise 3).
- `cancelOperation()` has no guard when nothing is running.
- R6 should consume `TransferReadiness` from step 4.5 rather than writing a second merged rule (its §2.3). R6's 100 MB recommendation conflicts with the runtime's 1 GB; see S-1.

---

## 9. Risks

- **Nested observables.** Adapters that read `coordinator.photographerJobViewModel.x` or `coordinator.folderInfoService.x` will not refresh unless the view observes the nested object. Because shared screens take values, this risk sits only in the adapters. Check every adapter during a live run.
- **Duplicate type names.** See §0.1. A shared type with a name already used in one target breaks that target's build.
- **iOS behaviour changes**, which are deliberate but visible:
  - Compare blocks same or nested folders.
  - Setup blocks below 1 GB of headroom (iOS used a 90% ratio).
  - iOS rejects bad destination picks at once.
  - The Advanced label changes.
  - "New transfer" behaviour changes (O-1).
  
  Record them in `CHANGELOG.md`.
- **Mac behaviour changes:** 1 GB headroom instead of 100 MB, the progress card finally shows a bar, and the completion screen gains Export and Retry.
- **Validation limits:** the simulator cannot prove security-scoped access to removable media, background-time behaviour, or Live Activities. Those need a physical iPhone or iPad, and each step must say which kind of validation it had.
