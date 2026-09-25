# Engine Package and Swift 6 Plan (Thesis Step 5)

> **For agentic workers:** This is a plan, not an implementation. Carry it out as **one commit per step in §9**, in order. Every commit must build both app targets and pass the tests it names: `bash test.sh mac-test` and `bash test.sh ipad-build` always; `bash test.sh ipad-test` (with `IOS_SIMULATOR_DESTINATION`) when a step touches `SafetyValidator`, `BackupTargetPolicy`, `DestinationSelectionPolicy`, `TransferReadiness` or anything under `#if os(iOS)`; and `swift test --package-path Packages/BitMatchEngine` from C22 on. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Move the code that makes promises 1–3 true (copy, verify, compare, checksums, ASC MHL, safety and backup-target rules, readiness, journal, evidence) into a local Swift package, `BitMatchEngine`, with no UI imports, tested against real folders. Then build the package, and after it the apps, in Swift 6 language mode. The Mac, iPad and iPhone apps become thin clients of one engine (promise 5).

**Target shape (from `docs/THESIS.md`):** `CardSource`, `DestinationWriter`, `ChecksumEngine`, `TransferPipeline`, `TransferJournal`, `EvidenceWriter`. The thesis's "one `@Observable` app model" is **not** part of this plan (§11).

**Method:** Everything here was worked out by reading `main` at **`31bc940`**. Nothing was compiled; this environment has no Xcode. The Swift 6 diagnostics in §7 are predictions. The dependency graph in §2 comes from a script that matches top-level type names across files (nested `Key`/`Entry`/`CodingKeys` false positives removed), and every edge named in §2 was checked by hand.

## What changed since the first draft (`08bae3f` → `31bc940`, 90 commits)

- **Done, dropped from the plan:** step 2 (operation state stored once in `OperationStateService`, verdict from results); step 3 (`AppCoordinator` and its four mirrored view models deleted; the Mac runs on `SharedAppCoordinator`); step 4 screens (Compare, History, Advanced, Master Report, Outcome, Setup, Progress, and the shared source/backup boxes); the typed `ResultOutcome` (`TransferModels.swift:74`) that writes and reads result text; Paranoid = byte-by-byte + SHA-256 everywhere (`VerificationMode.checksumTypes`, `CompareCheckPlan`); `DriveBenchmarkService` and `TransferEstimateModel` deleted (`ab7caf0`); the Quick-verdict and Paranoid questions (answered by THESIS Decisions); the iOS PDF question (decided: later, low priority); the benchmark question (decided: deleted). Old §8 (benchmark) and test T17 are gone.
- **New code the plan now places:** `BackupTargetPolicy` (`File/BackupTargetPolicy.swift`), `DestinationSelectionPolicy` and `TransferReadiness` (in `Models/`), `LiveProgressFeed` / `LiveResultsFeed` (`ViewModels/`), `CardLayoutClassifier` (`Camera/`), `ReportScanner`, `TransferSleepPreventer` (keep-awake seam used by `CopyVerifyExecutor`), the exFAT no-hard-link publish in `PinnedDestinationDirectory` (`c1bc33f`), `SafetyValidator`'s `/private` alias and iOS `/private/var/mobile` rules (`31bc940`).
- **New findings:**
  - `ResultsOverflowService` is written by `CopyVerifyExecutor` and never read in production (only `ResultsOverflowUpsertTests` calls `getAllResults`). Delete it (C04).
  - `ReportExporter`'s save panel, alerts, checksum re-export, issues export and legacy PDF path (≈350 lines, all the `NSAlert`/`NSSavePanel` use, and its `SharedChecksumService.shared` call) are unreachable. Delete them (C03). That removes most of the old "UI imports in engine files" blocker.
  - `FileCopyService.copyAllSafely` already takes a `pauseCheck` parameter; only the pinned-destination reads (`FileCopyService.swift:821`, `:855`) and `SharedChecksumService`'s chunk loops (`:187`, `:295`, `:340`, `:388`) still read the static `pauseCheck`.
  - After `ab7caf0` the engine's ETA (`OperationProgress.timeRemaining`, computed four times in `SharedFileOperationsService.swift` at `:605`, `:669`, `:743`, `:832`) feeds only the iOS Live Activity (`IOSBackgroundTaskService.swift:267`); the screen uses `ProgressPresentationModel`'s measured speed.
  - There are still **two free-space rules in the engine**: `SafetyValidator.performSafetyChecks` (manifest + 1 GB) and a second check in `SharedFileOperationsService.swift:421` (estimate + 100 MB). The decision is one rule, source + 1 GB (C09).
  - The JSON/CSV evidence contains made-up numbers (§12, Q3): `peakSpeedMBps = average × 1.2`, `copyDuration`/`verifyDuration = duration × 0.5`, and per-file CSV timestamps interpolated from the average rate.
  - Three path-containment helpers normalize paths differently: `SafetyValidator.pathIsWithin` (fixed in `31bc940`), `SafetyValidator.pathIsStrictlyWithin` and `BackupTargetPolicy.isWithin` (both still pre-`31bc940`). See C18.
  - The first draft's "71 test files" is now 100 files in `BitMatchTests` (all `@testable import BitMatch`) plus 6 in `BitMatch-iPadTests`.
- **Plan changes:** the step list is now 31 ordered commits (§9: C01–C30, with C17 split into C17a/C17b) instead of 8 stages. The package starts in Swift 5 language mode with complete checking and flips to Swift 6 one commit later (C21 → C23), so the move and the language change never land together. Concurrency consolidation (`RunLedger`, structured verification) moves **after** the package exists, where `swift test` gives fast feedback. The `ReportRenderer` protocol is dropped: the app renders the Mac PDF and hands the engine `Data`. The project-store migration (Core Data → JSON) is moved out of this plan (§11).

## 0. Constraints and sequencing

- **Promises first.** No step may change which bytes are read from the card, which files are written to a destination, or what a verdict says, except the three steps marked **behavior change** (C09, C18, and the optional evidence fix in §12 Q3), each of which follows a recorded decision or needs Mike's OK. Every guard test in §8 comes with a one-line plant that must turn it red; plant it once and watch it fail before relying on it.
- **Parallel sessions.** `cloud/tidy` deletes `ProgressPresentationModel.destinationProgressFractions` / `formattedFilesRemaining`, the `ContentView` completion helpers, `MacVolumeAccessModel.DriveSpeed` / `getOptimalWorkerCount` / `calculateCascadingDelays`, and possibly `SharedAppCoordinator.formattedTimeRemaining`. This plan treats them as gone and never touches them. `cloud/docs` owns `ARCHITECTURE.md`, `README.md`, `DEVELOPMENT.md` and `docs/THESIS.md`: the implementing session must not edit those in the commits below; hand doc updates (new `engine-test` job, package layout) to whoever owns docs after C22.
- **Toolchain.** CI runs Xcode 16.4 (Swift 6.1) on `macos-15` (`.github/workflows/ci.yml`). Deployment targets are iOS 18.5 and macOS 15.5, so `Synchronization.Mutex`/`Atomic` and `withThrowingDiscardingTaskGroup` are available. Swift 6.2 features (`nonisolated(nonsending)`, default main-actor isolation) are **not** used. App targets are `SWIFT_VERSION = 5.0` with `SWIFT_STRICT_CONCURRENCY = targeted` on the two app targets.
- **Project format.** `BitMatch.xcodeproj` uses file-system synchronized groups (`objectVersion = 77`). `Shared/` belongs to both app targets; `BitMatch/` to the Mac target (plus `Platforms/macOS/Services/MacOSPlatformManager.swift` by exception); `Platforms/` and `BitMatch-iPad/` to the iPad/iPhone target. Moving a file anywhere inside `Shared/` changes nothing for either target. The package must live **outside** every synchronized folder: `Packages/BitMatchEngine/` at the repository root. Adding it needs one pbxproj edit (C21).
- **Commit shape.** One commit per §9 step. Each lists the files it moves or changes, its access-level changes, what must compile after it, the tests the Mac session runs, and its risk. Commit messages end with the session's attribution lines.

## 1. Inventory (main at `31bc940`)

`Shared/Core/Services` has 36 top-level files plus `Camera/` (13), `File/` (4) and `Logging/` (1): 16,255 lines. `Shared/Core/Models` has 28 files (5,185 lines). `Shared/Core/ViewModels` has 5 files (1,807 lines).

| Concurrency and platform coupling | Files (in `Shared/Core`) |
|---|---|
| `@MainActor` classes | `ComparisonCoordinator`, `CopyVerifyExecutor`, `ErrorReportingService`, `FolderInfoService`, `IOSBackgroundTaskService` (iOS and the Mac stub), `LocalTransferJournal`, `OperationStateMachine`, `OperationStateService`, `OperationTimingService`, `SharedAppCoordinator`, `SharedReportGenerationService`, `TransferKeepAwake`, `UserDefaultsPhotographerJobStore`, `RemoteBackupCoordinator`, `PhotographerJobStoreRemoteBackupQueuePersistence`, `UnavailableRemoteProjectCoordinator`, `MasterReportModel`, `CameraLabelModel`, `LiveProgressFeed`, `LiveResultsFeed`, `PhotographerJobViewModel`, `ProgressPresentationModel`; protocols `PhotographerJobStore`, `ProjectRemoteCoordinator`; `@MainActor` members `ReportExporter.generatePDF`/`exportChecksumsAsync`, the `CopyVerifyCallbacks` closures and `PhotographerReportFinalizer` |
| actors | `AsyncSemaphore`, `SharedChecksumCache`, `ResultsOverflowService`, `RemoteBackupQueue`; in `SharedFileOperationsService`: `ResultStore` (:16), `VerifyCounter` (:32), `DestinationProgress` (:50), `ProgressState` (:70), `VerifyTaskStore` (:125), `PauseState` (:224); in `FileCopyService`: `_EnumeratorSource` (:331), `_ArraySource` (:361) |
| lock-guarded `@unchecked Sendable` | `ActiveOperationRegistry` (SFOS:151), `PermitQueue` (`AsyncSemaphore.swift:44`), `PinnedDestinationDirectory`/`PinnedDestinationFile` (immutable fd owners), `RemoteBackupArtifactLease`; `CameraMemoryService` uses `NSLock` but is not marked `Sendable` |
| `import SwiftUI` | `Models/SharedModels.swift` (`DriveType.color`), `Models/ResultStatusPresentation.swift`, `Services/ReportExporter.swift`, `Services/SharedAppCoordinator.swift` (`OperationReadinessAssessment.statusColor`), `Services/TransferHistoryDocument.swift`, `ViewModels/ProgressPresentationModel.swift` (`withAnimation`) |
| `import AppKit` / `UIKit` | `ReportExporter`, `SharedReportGenerationService`, `OperationStateService`, `SharedAppCoordinator`, `IOSBackgroundTaskService` (UIKit) |
| other platform frameworks | `ActivityKit`, `BackgroundTasks`, `UserNotifications` (`IOSBackgroundTaskService`, `SharedAppCoordinator`); `AVFoundation`, `ImageIO` (`CameraMemoryService`, `SharedCameraDetectionService`); `UniformTypeIdentifiers` (`ReportExporter`, `TransferHistoryDocument`); `CoreGraphics` (`AdaptiveNavigationPresentation`); `Combine` (7 files, all app-side) |
| whole-file `#if os(macOS)` | `RemoteBackupCoordinator`, `RemoteBackupProvider`, `RemoteBackupQueue` (SFTP, the explicit Mac exception) |
| Core Data | none in `Shared/`. `BitMatch/Core/Services/Photographer/{PhotographerJobStore,BitMatchPersistenceController}.swift`, `MacRemoteBackupController`, `MacAppEnvironment`, `PreferencesWindow` (Mac target only) |

## 2. Dependency graph (main at `31bc940`)

Arrows point to what a file uses. `SharedLogger` (portable `os.Logger`) and the `URL` helpers in `Shared/Core/Extensions/URLExtension.swift` (`relativePath(to:)`, `isAncestor(of:)`, `nonConflictingSibling()`) are used by most engine files and are left out.

### 2a. Engine core

```
SharedFileOperationsService (SFOS) ──► FileCopyService ──► PinnedDestinationDirectory/File (same file; exFAT publish :101, :129)
      │                                   │  ├──► SharedChecksumService.pauseCheck (static; :821, :855)
      │                                   │  └──► FileTreeEnumerator, RelativePathResolver, FileOperationError, ChecksumService
      ├──► SafetyValidator ──► BackupTargetPolicy (SafetyValidator.swift:79), FileTreeEnumerator, CameraLabelSettings
      ├──► FileTreeEnumerator (source manifest, SFOS:379)
      ├──► AsyncSemaphore (verify concurrency, SFOS:435)
      ├──► ServiceProtocols: FileSystemService, ChecksumService, FileOperation(Result), FileOperationsService
      ├──► OperationProgress, VerificationMode, BitMatchError, CameraLabelSettings
      ├──► SharedChecksumService.pauseCheck (sets/clears it, SFOS:347, :356)
      └──► UserDefaults.standard["DisablePipelinedVerify"] (SFOS:432)      ◄── app setting read inside the engine

SharedChecksumService ──► SharedChecksumCache (only when useCache == true; no production caller passes true)
                       ──► ChecksumService, ChecksumAlgorithm, VerificationResult, BitMatchError
FileOperationResult.outcome ──► ResultOutcome (ServiceProtocols.swift:116)
ResultRow.isSuccessStatus ──► ResultOutcome (TransferModels.swift:143)
ComparisonCoordinator (@MainActor) ──► PlatformManager (.fileSystem, .checksum), RelativePathResolver, OperationProgress,
                                       CompareCheckPlan ◄── declared in Models/ComparePresentation.swift:17
                                       CompareStats     ◄── declared in SharedAppCoordinator.swift:1424
ASCMHLGenerator ──► CryptoKit, Darwin, Bundle.main (:125)
TransferReadiness ──► SafetyValidator, BackupTargetPolicy (:74), CameraLabelSettings, VerificationMode
DestinationSelectionPolicy ──► SafetyValidator, BackupTargetPolicy (:158)
BackupTargetPolicy ──► (Foundation only)
LocalTransferJournal (@MainActor ObservableObject) ──► VerificationMode, CameraLabelSettings, ReportPrefs, ResultRow
ReportExporter ──► ReportSummary ──► PhotographerReportPayload (Models/PhotographerJobModels.swift), AppMode
               ──► ReportView (BitMatch/Views/ReportView.swift, Mac target) via ImageRenderer/NSHostingView
               ──► NSSavePanel, NSAlert (dead paths), Bundle.main (:185), SharedChecksumService.shared (:1046, dead path)
               ──► ResultRow, ReportPrefs, ChecksumAlgorithm, PhotographerReportContext
ReportScanner ──► TransferCard, TransferMetadata, FolderInfo, CameraCard/CameraType, OperationCompletionInfo, VerificationMode
ResultsOverflowService ──► ResultRow, ResultOutcome   (written by CopyVerifyExecutor, never read)
```

### 2b. Orchestration (mixed)

```
CopyVerifyExecutor (@MainActor) ──► PlatformManager.fileOperations (engine)
    ├──► SafetyValidator, ASCMHLGenerator, ReportExporter.export, ResultsOverflowService      (engine)
    ├──► verdict rule (:300): all rows succeed ∧ not Quick ∧ MHL ok ∧ report ok ∧ project gate (engine rule, app code today)
    └──► OperationStateService, OperationTimingService, ErrorReportingService, IOSBackgroundTaskService,
         TransferKeepAwake/TransferSleepPreventing, PhotographerReportFinalizer, NotificationCenter(.operationCompleted),
         PlatformManager.presentError                                                        (app)
SharedAppCoordinator ──► everything above, LocalTransferJournal, ComparisonCoordinator, TransferReadiness,
                         BackupTargetPolicy, FolderInfoService, LiveProgressFeed, LiveResultsFeed,
                         ProgressPresentationModel, CameraLabelModel, PhotographerJobViewModel,
                         ReportPrefsStore, TransferHistoryDocument, both PlatformManagers
```

### 2c. Around the engine (app)

```
Camera/* (11 detectors, CleanCameraNameService) ──► CameraDetectionOrchestrator ──► CardLayoutClassifier ──► CameraType
SharedCameraDetectionService (AVFoundation, [String: Any]) ──► CameraDetectionOrchestrator, CardLayoutClassifier
CameraStructureDetector ──► CardLayoutClassifier (mediaPath is always the card root since 40846dd)
CameraLabelModel (@MainActor) ──► Task.detached over CameraDetectionOrchestrator.shared, CameraMemoryService.shared, CleanCameraNameService.shared
PhotographerJobModels ◄──► PhotographerCardAnalyzer, PhotographerJobPresentation (RemoteBackupStatusPresentation)
RemoteBackup{Coordinator,Queue,Provider} (#if os(macOS)) ──► KeychainHelper (BitMatch/Utilities, Mac target)
MasterReportModel (@MainActor, in Models/) ──► ReportScanner, SharedReportGenerationService
LiveProgressFeed, LiveResultsFeed, ProgressPresentationModel ◄── SharedAppCoordinator (fed from engine callbacks)
```

### 2d. Fan-out

About 80 app files (60 in `Shared/`, 14 in `BitMatch/`, 3 in `Platforms/`, 3 in `BitMatch-iPad/`) and about 67 test files reference at least one engine type. Production entry points into the pipeline are few (`MacOSPlatformManager.swift:19`, `IOSPlatformManager`, `CopyVerifyExecutor.swift:162`, `ComparisonCoordinator`), so the move is mostly about imports, access control and tests. C21 uses one `@_exported import BitMatchEngine` shim so the move commit does not touch 147 files (§4g).

## 3. Classification

**E** = engine package. **A** = app. **S** = split the file. **D** = delete.

| File | Class | Step | Notes |
|---|---|---|---|
| `File/FileCopyService.swift` | E | C19 | Pinned descriptors, atomic no-replace publish incl. exFAT claim-then-rename (`publishByClaimingName`, :129), reuse check. Stays `internal` to the package; tested from package tests. Thesis name `DestinationWriter` (C27). |
| `File/SafetyValidator.swift` | E | C19 | Keeps its `#if os(iOS)` user-storage rule (:528); the package compiles per platform, so the iOS branch is only exercised by `BitMatch-iPadTests/IOSStoragePathTests`. |
| `File/BackupTargetPolicy.swift` | E | C19 | Pure rule plus `VolumeFacts.read`. |
| `File/FileTreeEnumerator.swift` | E | C19 | Core of `CardSource`. |
| `SharedFileOperationsService.swift` | E | C19 | `TransferPipeline` (C27). |
| `SharedChecksumService.swift` | E | C19 | `ChecksumEngine` (C27). Static `pauseCheck` removed in C07. |
| `ChecksumCache.swift` | D | C05 | No production path passes `useCache: true`. |
| `AsyncSemaphore.swift` | D | C26 | Replaced by a task group. |
| `ResultsOverflowService.swift` | D | C04 | Written, never read. |
| `ASCMHLGenerator.swift` | E | C19 | Part of `EvidenceWriter`; tool version becomes a parameter (C15). |
| `LocalTransferJournal.swift` | S | C17 | Records, resources, access, persistence → engine `TransferJournal`; `ObservableObject` wrapper stays app. |
| `ComparisonCoordinator.swift` | S | C14 | Engine `FolderComparer`; thin `@MainActor` wrapper stays app. |
| `ReportExporter.swift` | S | C03, C15 | CSV, JSON, checksum manifest, save location → engine `EvidenceWriter`. PDF rendering (`ReportView`) stays app. |
| `ReportScanner.swift` | S | C16 | JSON decoding and classification → engine `EvidenceReader`; mapping to `TransferCard` stays app. |
| `ServiceProtocols.swift` | S | C11 | Engine: `ChecksumService`, `FileAccess` (new), `FileOperationsService`, `FileOperation`, `FileOperationResult`. App: `FileSystemService` (pickers, refines `FileAccess`), `CameraDetectionService`, `PlatformManager`. |
| `CopyVerifyExecutor.swift` | S | C17 | Engine `TransferCompletion` (row mapping, ASC MHL eligibility and write, verdict). App executor keeps services, keep-awake, background task, project finalizer. |
| `Logging/SharedLogger.swift`, `Extensions/URLExtension.swift` | E | C13, C19 | Public so the app keeps using them. |
| `TransferSleepPreventer.swift` | A | — | Keep-awake seam; lifecycle, not evidence. |
| `OperationStateService`, `OperationStateMachine`, `OperationTimingService`, `ErrorReportingService`, `IOSBackgroundTaskService`, `FolderInfoService`, `SharedAppCoordinator`, `SharedReportGenerationService`, `TransferHistoryDocument`, `ReportPrefsStore` | A | — | UI state, platform lifecycle, Master Report PDF, file export. |
| `Camera/*` incl. `CardLayoutClassifier`, `CameraMemoryService`, `CameraNamingService`, `CameraStructureDetector`, `SharedCameraDetectionService` | A | — | Naming and brand detection. The whole-card rule lives in `CameraStructureDetector` (40846dd), not the classifier. `CardLayoutClassifier`/`CardListing` are pure Foundation and could become a second package target later (§5, §12 Q5). |
| `Photographer*`, `FolderRecipeRenderer`, `ProjectStoreProtocol`, `ProjectRemoteCoordinator`, `UserDefaultsPhotographerJobStore`, `RemoteBackup*` | A | — | Opt-in features (promise 4) and the SFTP exception. The engine sees project data only as `ProjectEvidence` (C15). |
| `Models/SharedModels.swift` | S | C13 | Engine: `ChecksumAlgorithm`, `BitMatchError`, `VerificationResult`, `VerificationMode`. App: `AppMode`, `FolderInfo`, `EnhancedFolderInfo`, `DriveType` (SwiftUI), `FolderDisplayInfo`, `Notification.Name`s. |
| `Models/CameraModels.swift` | S | C13 | Engine: `CameraLabelSettings` (decides the destination root: a safety input). App: `CameraType`, `CameraCard`, `CameraDetectionResult` (`[String: Any]`). |
| `Models/OperationModels.swift` | S | C13 | Engine: `OperationProgress`, `ProgressStage`. App: `OperationState`, `PauseInfo`, `OperationCompletionInfo`, `CompletionState`, `VolumeEvent`. |
| `Models/TransferModels.swift` | S | C13 | Engine: `ResultOutcome`, `ResultRow`, `ReportPrefs`. App: `TransferCard`, `TransferMetadata`, `AutomaticSourceSelectionPolicy`. |
| `Models/ComparePresentation.swift` | S | C13 | Engine: `CompareCheckPlan` (the engine's check list). App: the rest. |
| `Models/TransferReadiness.swift`, `Models/DestinationSelectionPolicy.swift` | E | C19 | Rules shared by every platform (promise 5). Move from `Models/` to the engine. |
| `Models/ReportSummary.swift` | A | — | Only the Mac PDF (`ReportView`) reads it after C15. |
| `Models/MasterReportModel.swift` | A | — | An `@MainActor` view model filed under `Models/`. |
| every other `*Presentation.swift`, `NotificationPermissionPolicy` | A | — | Presentation. |
| `ViewModels/*` (`LiveProgressFeed`, `LiveResultsFeed`, `ProgressPresentationModel`, `CameraLabelModel`, `PhotographerJobViewModel`) | A | — | `@MainActor` observable state fed by the engine's callbacks. |

## 4. What blocks the move

### 4a. UI and platform imports in engine files

1. `ReportExporter.swift`: `SwiftUI`, `AppKit`/`UIKit`, `UniformTypeIdentifiers`. After C03 (dead code) only `generatePDF` (:262, `@MainActor`, `ImageRenderer(content: ReportView(...))`) remains. **Fix (C15):** the app renders the PDF and passes `pdf: Data?` to `EvidenceWriter`. No renderer protocol.
2. `SharedModels.swift` imports SwiftUI for `DriveType.color`. **Fix (C13):** `DriveType` stays in the app file; the engine models move to their own file.
3. `Bundle.main` in `ReportExporter.swift:185` and `ASCMHLGenerator.swift:125`. **Fix (C15):** `appVersion` / `toolVersion` parameters.
4. `CompareStats` lives in `SharedAppCoordinator.swift:1424` (a SwiftUI/AppKit/UIKit file); `CompareCheckPlan` in `ComparePresentation.swift:17`. **Fix (C13).**

### 4b. `@MainActor` on engine types

1. `LocalTransferJournal` (`LocalTransferJournal.swift:172`). **Fix (C17):** engine `final class TransferJournal: Sendable` with state in `Mutex` and the **same synchronous throwing API**; the app's `LocalTransferJournal` wraps it and republishes `records`/`persistenceError`. `LocalTransferAccess` (`:132`, mutable `scopedURLs`) becomes `Sendable` (`Mutex`-guarded, release-once).
2. `ComparisonCoordinator` (`:5`) keeps its cancel flag as main-actor state and calls `platformManager.fileSystem`/`.checksum`. **Fix (C14):** `FolderComparer: Sendable` over `FileAccess` + `ChecksumService`; task cancellation; the app wrapper keeps `requestCancellation()`/`isCancellationRequested` for `SharedAppCoordinator`.
3. `CopyVerifyExecutor` (`:66`) with `@MainActor` callbacks and `PhotographerReportFinalizer` (`:13`). **Fix (C17):** extract the pure engine half as `TransferCompletion`; the executor stays `@MainActor` in the app.
4. `ReportExporter.generatePDF` (`@MainActor`) stays app with the PDF.

### 4c. Core Data

None in `Shared/`, so it does not block the package. It remains a promise-5 inconsistency (Mac jobs in Core Data, iOS jobs in `UserDefaults`, transfers in JSON); §11 keeps it as an independent track.

### 4d. Singletons and global state

| Global | Where | Fix |
|---|---|---|
| `static var pauseCheck` | `SharedChecksumService.swift:8` | Deleted in C07 (explicit `PauseGate`). |
| `static let shared` (non-final class) | `SharedChecksumService.swift:7` | C12: `final class SharedChecksumService: ChecksumService, Sendable` (stateless after C05/C07); keep `shared` for the app. |
| `static let shared` (actor) | `ChecksumCache.swift:6` | Deleted in C05. |
| `MacOSPlatformManager.shared`, `._sharedFileOperations`, `._sharedCameraDetection`; `IOSPlatformManager.shared`; `MacOSFileSystemService.shared`; `IOSFileSystemService.shared` | `Platforms/`, `BitMatch/Core/Services/Platform/` | App side. C12 makes the file-access and pipeline values `Sendable`; C28 finishes the managers. |
| 12 camera `static let shared` + `CameraMemoryService.shared` | `Camera/*`, `CameraMemoryService.swift:8` | App side, C28 (stateless → `Sendable`; `CameraMemoryService` → `Mutex` or `@unchecked Sendable` with a comment). |
| `IOSBackgroundTaskService.shared` | `IOSBackgroundTaskService.swift:17`, `:294` | `@MainActor` class, so isolated; fine. |

### 4e. `UserDefaults` and bundle reads in engine code

Only one in engine code: `SharedFileOperationsService.swift:432` (`DisablePipelinedVerify`). **Fix (C08):** an init parameter set by the two platform managers. All other `UserDefaults` use (`SharedAppCoordinator`, `ReportPrefsStore`, `CameraLabelModel`, `CameraMemoryService`, `IOSBackgroundTaskService`, `OperationStateService`, `UserDefaultsPhotographerJobStore`) is app code. `Bundle.main`: §4a.3.

### 4f. References from engine files to app code

| Reference | From | Fix |
|---|---|---|
| `CompareStats`, `CompareCheckPlan` | `ComparisonCoordinator` | Move both to the engine (C13). |
| `PlatformManager` | `ComparisonCoordinator`, `CopyVerifyExecutor` | `FolderComparer` takes `FileAccess` + `ChecksumService` (C14); the executor stays app. |
| `ReportView`, `ReportSummary` | `ReportExporter` | The app renders the PDF (C15). |
| `PhotographerReportContext`, `PhotographerReportPayload` | `ReportExporter` (CSV columns, JSON `photographyJob`, CSV summary rows) | `ProjectEvidence` (C15): the CSV fields as plain values and the JSON section as an `Encodable & Sendable` box. JSON uses `.sortedKeys` (`ReportExporter.swift:738`), so an encoding box produces the same bytes; T14 proves it. |
| `AppMode` | `ReportExporter` (save location, JSON `mode` string) | `EvidenceKind` with the same raw values (`"Copy & Verify"`, …) so the JSON is unchanged. |
| `TransferCard`, `FolderInfo`, `CameraCard` | `ReportScanner` | Engine returns `ReportSnapshot`; app maps (C16). |
| `FileSystemService` pickers | `SharedFileOperationsService`, `ComparisonCoordinator` | `FileAccess` (C11). |

### 4g. Language, access and build blockers

1. **Implicit `Sendable` is lost at `public`.** Internal structs/enums with `Sendable` members are inferred `Sendable`; public ones are not. Every public engine value type declares `Sendable` explicitly (C20). `FileOperationResult.error: Error?` is fine.
2. **Existentials and callbacks.** `any ChecksumService` and `FileSystemService` are captured in `Task {}` and `group.addTask {}`; `FileOperationsService.ProgressCallback`/`FileResultCallback` and `FileCopyService`'s `onProgress`/`onError` are not `@Sendable`. **Fix (C12).**
3. **Public default arguments.** `DestinationSelectionPolicy.evaluateBackup/evaluateSource/addBackups` default to `itemKind`, `isMacSystemFolder`, `userChoiceRefusal`; `BackupTargetPolicy.refusal` defaults to `VolumeFacts.read` and `FileManager.default.temporaryDirectory`. Those must be `public` too.
4. **Memberwise initializers are internal.** Engine structs the app constructs (`CameraLabelSettings`, `ReportPrefs`, `OperationProgress` has explicit inits, `VerificationResult`, `TransferReadiness`, `FileOperationResult`, `ASCMHLGenerator.VerifiedFile`) need explicit `public init`s (C20).
5. **Tests use `@testable`.** Tests that reach engine internals (`PinnedDestinationDirectory.open`, `FileCopyService.copyAllSafely`, `ExistingDestinationReuseTests`, `ExFATDestinationTests`) move to the package in C22 or use `@testable import BitMatchEngine`.
6. **Imports.** ~147 files would need `import BitMatchEngine`. C21 adds one app file, `Shared/App/BitMatchEngineExports.swift`, containing `@_exported import BitMatchEngine`; explicit imports can replace it later.

## 5. Proposed public API (today's types)

C20 makes this surface `public` under **today's names**; C27 optionally renames to the thesis names with deprecated typealiases. Nothing here changes what is copied, verified or reported.

```swift
// Packages/BitMatchEngine/Sources/BitMatchEngine

// Values -------------------------------------------------------------------
public enum VerificationMode: String, CaseIterable, Identifiable, Codable, Sendable   // + checksumTypes, useChecksum, requiresMHL, description
public enum ChecksumAlgorithm: String, CaseIterable, Identifiable, Codable, Sendable
public struct VerificationResult: Codable, Sendable                                    // + public init, isValid
public enum BitMatchError: LocalizedError, Sendable
public struct CameraLabelSettings: Codable, Sendable                                   // + public init(), formattedFolderName, sanitizePathComponent
public struct OperationProgress: Codable, Sendable; public enum ProgressStage: Codable, Sendable

/// How one file on one backup ended (TransferModels.swift:74). The only producer of result text,
/// and the only reader: `ResultRow.isSuccessStatus` parses back through it; unknown text is never success.
public enum ResultOutcome: CaseIterable, Equatable, Sendable {
    case verified, copiedUnverified, checksumMismatch, failed
    public var statusText: String { get }
    public var isSuccess: Bool { get }      // verified || copiedUnverified — "copied", never "verified"
    public var isVerified: Bool { get }     // only .verified is green (CompletionVerdict, a062412)
    public init?(statusText: String)
}
public struct ResultRow: Identifiable, Sendable {                                      // unchanged fields; public init
    public var isSuccessStatus: Bool { get }
    public static func isSuccessStatus(_ status: String) -> Bool                       // older text: fail-safe "✅" rule
}
public struct ReportPrefs: Codable, Sendable                                           // persisted by app and journal (debt: mixes UI prefs)

// Rules (Mac, iPad and iPhone call the same code) --------------------------
public enum BackupTargetPolicy {
    public enum Origin: Equatable, Sendable { case userChoice, restored, discovered }
    public struct VolumeFacts: Equatable, Sendable { public static func read(_ url: URL) -> VolumeFacts?; /* fields */ }
    public static func refusal(for target: URL, origin: Origin, source: URL?,
                               facts: (URL) -> VolumeFacts? = VolumeFacts.read,
                               temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> String?
    public static func isSystemVolumeName(_ name: String) -> Bool
    public static func canonicalPath(_ url: URL) -> String
}
public final class SafetyValidator {   // static API; FolderOverlap, requiredHeadroomBytes (1 GB), destinationSafetyIssue,
                                       // resolvedDestinationRoot(Checked), destinationRootComponents, isProtectedSystemPath,
                                       // performSafetyChecks, performComparisonChecks, checkedRequiredSpace, …
}
public enum FileOperationError: LocalizedError, Equatable, Sendable
public enum DestinationSelectionPolicy {   // Decision, ItemKind, evaluateBackup, evaluateSource, addBackups,
                                           // itemKind, isMacSystemFolder, userChoiceRefusal (public: used as defaults)
}
public struct TransferReadiness: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case needsSource, needsDestination, analysing, blocked, ready }
    public let status: Status; public let blockers: [String]; public let warnings: [String]
    public static let requiredHeadroomBytes: Int64
    public static func assess(source: URL?, sourceBytes: Int64?, isAnalysingSource: Bool, destinations: [URL],
                              settings: CameraLabelSettings, verificationMode: VerificationMode,
                              availableBytes: (URL) -> Int64?, isWritable: (URL) -> Bool) -> TransferReadiness
    public static func isWritableFolder(_ url: URL) -> Bool
}

// Source and checksums ------------------------------------------------------
public struct FileEntry: Sendable { public let url: URL; public let relativePath: String; public let size: Int64; public let modificationDate: Date? }
public struct RelativePathResolver: Sendable
public enum FileTreeEnumerator { public static func enumerateRegularFiles(base: URL) throws -> [FileEntry] }   // fail-closed

public protocol FileAccess: Sendable {            // today's FileSystemService minus the pickers (C11)
    func validateFileAccess(url: URL) async -> Bool
    func startAccessing(url: URL) -> Bool; func stopAccessing(url: URL)
    func getFileList(from folderURL: URL) async throws -> [URL]
    func getFileSize(for url: URL) throws -> Int64
    func createDirectory(at url: URL) throws
    func freeSpace(at url: URL) -> Int64
}
public protocol ChecksumService: Sendable {       // useCache removed (C05); pause gate explicit (C07)
    typealias ProgressCallback = @Sendable (Double, String?) -> Void
    func generateChecksum(for: URL, type: ChecksumAlgorithm, pauseGate: PauseGate?, progressCallback: ProgressCallback?) async throws -> String
    func verifyFileIntegrity(sourceURL: URL, destinationURL: URL, type: ChecksumAlgorithm, pauseGate: PauseGate?, progressCallback: ProgressCallback?) async throws -> VerificationResult
    func performByteComparison(sourceURL: URL, destinationURL: URL, pauseGate: PauseGate?, progressCallback: ProgressCallback?) async throws -> Bool
}
public final class SharedChecksumService: ChecksumService, Sendable { public static let shared: SharedChecksumService }
public final class PauseGate: Sendable { public init(); public func pause(); public func resume(); public func wait() async throws }

// Pipeline ------------------------------------------------------------------
public struct FileOperation: Sendable; public struct FileOperationResult: Sendable { public var outcome: ResultOutcome { get } }
public protocol FileOperationsService: Sendable {
    typealias ProgressCallback = @Sendable (OperationProgress) -> Void
    typealias FileResultCallback = @Sendable (FileOperationResult) async -> Void
    func performFileOperation(sourceURL: URL, destinationURLs: [URL], verificationMode: VerificationMode,
                              settings: CameraLabelSettings, estimatedTotalBytes: Int64?,
                              progressCallback: @escaping ProgressCallback, onFileResult: FileResultCallback?) async throws -> FileOperation
    func cancelOperation(); func pauseOperation() async; func resumeOperation() async
}
public final class SharedFileOperationsService: FileOperationsService, Sendable {
    public init(fileSystem: any FileAccess, checksum: any ChecksumService, pipelinedVerification: Bool = true,
                destinationSetupHook: (@Sendable (URL) throws -> Void)? = nil)       // hook = existing test seam
}
// FileCopyService, PinnedDestinationDirectory/File (incl. the exFAT publishByClaimingName fallback) stay internal:
// only the pipeline and package tests call them.

// Completion, compare, journal, evidence -------------------------------------
public enum TransferCompletion {                  // the pure half of CopyVerifyExecutor (C17)
    public static func rows(from: FileOperation) -> [ResultRow]                              // incl. today's driveName(for:)
    public static func ascmhlPlan(for: FileOperation, destinations: [URL], source: URL,
                                  settings: CameraLabelSettings) -> (jobs: [ASCMHLJob], issues: [String])
    public static func writeASCMHL(_ jobs: [ASCMHLJob], startTime: Date, source: URL, toolVersion: String) async throws -> [String]
    public static func verdict(rows: [ResultRow], mode: VerificationMode, handoffIssues: [String],
                               reportIssue: String?, projectGate: ProjectGate?) -> (success: Bool, message: String)
}
public enum ASCMHLGenerator {
    public struct VerifiedFile: Sendable { public init(relativePath: String, size: Int64, expectedSHA256: String) }
    public static func generateInitialHistory(destinationURL: URL, files: [VerifiedFile], startTime: Date,
                                              sourceURL: URL?, toolVersion: String) throws -> URL
}
public struct CompareCheckPlan: Equatable, Sendable { public static func make(for: VerificationMode) -> Self }
public struct CompareStats: Equatable, Sendable
public struct FolderComparer: Sendable {
    public init(fileAccess: any FileAccess, checksum: any ChecksumService)
    public func compare(left: URL, right: URL, mode: VerificationMode,
                        progress: @Sendable (OperationProgress) -> Void) async throws -> CompareStats
    public static func isFinderMetadata(_ relativePath: String) -> Bool                     // GitHub #8
    public static func isOffloadManifest(_ relativePath: String) -> Bool
}
public final class TransferJournal: Sendable {    // same synchronous API as LocalTransferJournal today
    public init(fileURL: URL?) ; public var records: [LocalTransferRecord] { get }; public var persistenceError: String? { get }
    public func enqueue(…) throws -> UUID; public func requeue(id:generateASCMHL:) throws -> UUID
    public func prepareToRun(id:) throws -> LocalTransferAccess; public func staleResourceIndexes(id:) throws -> [Int]
    public func reauthorize(id:resourceIndex:newURL:) throws; public func markRunning(id:) throws
    public func finish(id:results:summary:hadIssues:) throws; public func interrupt(id:summary:results:) throws
    public func cancel(id:summary:results:) throws
}
public struct LocalTransferRecord: Identifiable, Codable, Sendable; public enum LocalTransferState: String, Codable, Sendable
public final class LocalTransferAccess: Sendable { public func release() }
public enum EvidenceKind: String, Sendable { case copyAndVerify = "Copy & Verify", compareFolders = "Compare Folders", masterReport = "Master Report" }
public struct ProjectEvidence: Sendable {         // CSV columns + summary rows + JSON section, built by the app from PhotographerReportPayload
    public init(csv: ProjectCSVFields, json: (any Encodable & Sendable)?)
}
public enum EvidenceWriter {                      // today's ReportExporter minus UI
    public static func reportFileName(finished: Date, pathExtension: String) -> String
    public static func verificationDescription(for: ReportPrefs) -> (method: String, label: String, algorithm: String?, primaryAlgorithm: ChecksumAlgorithm?)
    public static func export(kind: EvidenceKind, jobID: UUID, started: Date, finished: Date, sourceURL: URL?,
                              destinationURLs: [URL], results: [ResultRow], fileCount: Int, matchCount: Int,
                              prefs: ReportPrefs, workers: Int, totalBytesProcessed: Int64, generateFullReport: Bool,
                              project: ProjectEvidence?, pdf: Data?, appVersion: String) async throws
    public static func makeEnhancedCSV(…) throws -> String; public static func makeEnhancedJSONReport(…) throws -> EnhancedJSONReport
    public static func writeRecordedChecksumManifest(results: [ResultRow], algorithm: ChecksumAlgorithm, to: URL) throws
}
public enum EvidenceReader {                      // today's ReportScanner minus TransferCard (C16)
    public static let maxReportBytes: Int
    public struct ReportSnapshot: Sendable { /* the fields ReportScanner.Snapshot decodes */ }
    public static func scanReports(at root: URL, day: Date, calendar: Calendar) async -> (reports: [ReportSnapshot], skipped: [SkippedReport])
    public static func verificationMode(method: String?, algorithm: String?) -> VerificationMode?
    public static func isVerified(matches: Int, issues: Int, mode: VerificationMode?) -> Bool
}
public enum SharedLogger { /* unchanged */ }
extension URL { public func relativePath(to:) -> String; public func isAncestor(of:) -> Bool; public func nonConflictingSibling(maxAttempts:) -> URL }
```

**Kept in the app, with the reason:**

- `CopyVerifyExecutor`: orchestration over app services (`OperationStateService`, timing, errors, `IOSBackgroundTaskService`, `TransferKeepAwake`, `PhotographerReportFinalizer`). After C17 it calls `TransferCompletion` for every engine decision.
- `CardLayoutClassifier` / `CardListing` / `CardLayoutMatch`: brand and naming, not safety (§3). If Mike wants it shared as code rather than as a file in `Shared/` (§12 Q5), the natural home is a second library target in the same package: `public enum CardLayoutClassifier { public static func classify(at: URL) -> CardLayoutMatch?; public static func classify(_: CardListing) -> CardLayoutMatch?; public static func brandName(for: CameraType) -> String? }`, which also needs `CameraType` public.
- `LiveProgressFeed`, `LiveResultsFeed`, `ProgressPresentationModel`: `@MainActor` observable state. They consume the engine's `OperationProgress` and `ResultRow` values unchanged.

## 6. Consolidating concurrency (C24–C26)

**Today, per run:** `ActiveOperationRegistry` (NSLock), `PauseState` (actor, polled every 100 ms), the static `pauseCheck`, `ResultStore`, `VerifyCounter`, `DestinationProgress`, `ProgressState`, `VerifyTaskStore` (200-task FIFO), `AsyncSemaphore` + `PermitQueue`, `_ArraySource` and (tests only) `_EnumeratorSource`. Nine state holders and one global. The global is a real hazard: a second `SharedFileOperationsService` or a Compare checksumming while a copy is paused blocks on the first run's pause, and when the first run ends it clears the hook for everyone.

**Target:** one `PauseGate` per service (C06–C07), one `Mutex` for run admission (C24), one `Atomic<Int>` manifest index (C24), one `RunLedger` actor per run (C25) replacing the four progress/result actors with a `ProgressDecision` that owns the throttle and the "first and last always emit" rule, and one `withThrowingDiscardingTaskGroup` per destination for verification fed through a bounded hand-off (C26). No unstructured tasks, no globals. `PinnedDestinationDirectory`/`File` stay `@unchecked Sendable` (immutable fds closed in `deinit`); add a comment saying why.

**Invariants (each has a test in §8):**
- I1. A second `start` while a run is active throws `operationAlreadyInProgress`.
- I2. A cancel that arrives before the run task is attached still cancels it.
- I3. Cancelling waits for in-flight verifies before returning. No verify outlives its run.
- I4. Cancelling during destination setup produces no failure rows.
- I5. A pause left from a previous run does not block the next run.
- I6. A verify result is never replaced by the copy row for the same (source, destination). Today this holds by construction: the copy row is delivered before its verify task exists. `LiveResultsFeed.upsert` has no supersede rule of its own (the deleted `ResultsOverflowService.canReplace` had one), so the ledger must keep the ordering guarantee.
- I7. Verify concurrency never exceeds `max(2, cores/2)`, and queued verify jobs stay bounded.
- I8. While paused, no new file starts copying and no checksum chunk is read.
- I9. Pausing one run does not pause another run or a Compare.
- I10. An inaccessible destination produces failure rows for that destination only; the others still run.

## 7. What Swift 6 will flag, file by file (predictions)

Swift 6.1 semantics: SE-0414 region isolation, SE-0434 (global-actor-isolated closures are `Sendable`), static/global `let` of a non-`Sendable` type is an error. "Error" = error in Swift 6 mode, warning under `SWIFT_STRICT_CONCURRENCY = complete` in Swift 5 mode. "Fixed by" names the §9 step.

| File | Predicted diagnostics | Fixed by |
|---|---|---|
| `SharedChecksumService.swift` | **Error:** `static var pauseCheck` is global mutable state (:8). **Error:** `static let shared` of a non-final, non-`Sendable` class (:7). | C07, C12 |
| `SharedFileOperationsService.swift` | **Error:** `Task { try await executeOperation(...) }` (:278) and the verify `Task { [verifySemaphore] in … self … }` (:567) capture non-`Sendable` `self` (non-final class) and the non-`@Sendable` `progressCallback`/`onFileResult`. **Error:** `fileSystem: FileSystemService` and `checksumService: any ChecksumService` are non-`Sendable` existentials captured in escaping closures. **Warning:** writes to the static `pauseCheck` (:347, :356). | C07, C11, C12 |
| `File/FileCopyService.swift` | **Error:** `group.addTask` captures `onProgress`/`onError` (escaping, not `@Sendable`) and `checksumService` (:376–466). **Error:** reads the static `pauseCheck` (:821, :855). `PinnedDestination*` `@unchecked Sendable`: clean. The exFAT fallback is plain Darwin calls: clean. | C07, C12 |
| `ServiceProtocols.swift` | **Error, knock-on:** non-`@Sendable` `ProgressCallback`/`FileResultCallback`; `nonisolated` requirements on a non-isolated protocol are redundant (warning). `CameraDetectionService` returns `[String: Any]` from `async` methods (error when called across isolation). | C11, C12 (engine); C28 (camera) |
| `ChecksumCache.swift` | Clean (actor). Deleted. | C05 |
| `AsyncSemaphore.swift` | Probably clean. Deleted. | C26 |
| `ResultsOverflowService.swift` | Clean. Deleted. | C04 |
| `File/SafetyValidator.swift`, `File/BackupTargetPolicy.swift`, `File/FileTreeEnumerator.swift`, `ASCMHLGenerator.swift` | Clean: static functions over `Sendable` constants. Public types need explicit `Sendable` (C20). | C20 |
| `Models/TransferReadiness.swift`, `Models/DestinationSelectionPolicy.swift` | Clean (already `Sendable` where it matters). Public default arguments must be public (§4g.3). | C20 |
| `LocalTransferJournal.swift` | Clean today because it is `@MainActor`. The engine version needs `LocalTransferAccess: Sendable` (mutable `scopedURLs`). `deinit` touches only `Int32` state: clean. | C17 |
| `ComparisonCoordinator.swift` | **Likely error:** a `@MainActor` object sends its stored non-`Sendable` existentials (`platformManager.checksum`, `.fileSystem`) into nonisolated async calls (:127, :136, :48). | C14 |
| `CopyVerifyExecutor.swift` | **Likely error:** `platformManager.fileOperations.performFileOperation` sends a non-`Sendable` existential from the main actor (:162). The two `Task.detached` blocks (:377, :453) capture only implicitly-`Sendable` values: clean while those types are internal, and explicit `Sendable` keeps them clean after C20. | C12, C17 |
| `ReportExporter.swift` | **Error:** `showErrorAlert`, `showInfoAlert`, `showSavePanel`, `askToExportChecksums`, `exportIssuesOnly` build `NSAlert`/`NSSavePanel` (`@MainActor`) from nonisolated statics. All dead. `MainActor.run { generatePDF(...) }` needs `ReportSummary` and `[ResultRow]` `Sendable` (implicit today). | C03, C15 |
| `ReportScanner.swift` | Probably clean (`async` static over `Sendable` values). `TransferCard` has `let id = UUID()` and `CameraCard.metadata: [String: Any]`: non-`Sendable` if returned across isolation. | C16 |
| `TransferSleepPreventer.swift` | Clean: `ProcessInfoSleepPreventer` is a stateless struct, `TransferKeepAwake` is `@MainActor`. | — |
| `OperationStateService.swift` | **Possible error:** `DispatchQueue.main.asyncAfter { [weak self] … self.applyTransition(...) }` (:152) calls main-actor methods from a `@Sendable` closure unless the compiler's `DispatchQueue.main` special case covers `asyncAfter`. Selector-based observers (:250–:271) compile clean. | C29 |
| `IOSBackgroundTaskService.swift` | **Possible error:** `beginBackgroundTask` expiration handler (:102) calling a main-actor method; `Task { await act.update(content) }` (:274) sends `Activity` (depends on ActivityKit's `Sendable` annotations). The `Timer` closure hops with `Task { @MainActor }`: clean. | C29 |
| `FolderInfoService.swift` | `Task.detached { [weak self] … self.scan…() }` (:51, :83, :115) calls `nonisolated` scanners and returns `EnhancedFolderInfo` (tuple member; implicitly `Sendable` while internal): probably clean. | C28 |
| `CameraLabelModel.swift` | **Error** at each singleton it uses from `Task.detached` (:48), reported at the declarations below. | C28 |
| `Camera/*` (12), `CameraMemoryService.swift` | **Error ×13:** `static let shared` of non-`Sendable` `final class`. Detectors are stateless (mark `Sendable`); `CameraMemoryService` holds `memory` under `NSLock` (:35): `Mutex` or `@unchecked Sendable` with a comment. `CardLayoutClassifier`, `CardListing`: clean. | C28 |
| `SharedCameraDetectionService.swift` | **Error:** non-final class conforming to `CameraDetectionService`, stored in `MacOSPlatformManager._sharedCameraDetection` (static); `[String: Any]` results. | C28 |
| `FolderRecipeRenderer.swift` | `private static let dateFormatter: DateFormatter` (:24): **possible error**, depending on the SDK's `Sendable` annotation for `DateFormatter`. | C28 |
| `RemoteBackupQueue.swift`, `RemoteBackupCoordinator.swift`, `RemoteBackupProvider.swift` | Already heavily `Sendable`. Expect only knock-on errors where `@MainActor` `PhotographerJobStore` values cross into the actor. | C28 |
| `CopyVerifyExecutor` callbacks into `LiveProgressFeed` / `LiveResultsFeed` / `ProgressPresentationModel` | Clean: all `@MainActor`; `ProgressPresentationModel`'s `Timer` closure hops with `Task { @MainActor }` (:86). | — |
| `SharedAppCoordinator.swift` | Combine `sink` closures formed in main-actor context: clean. Largest consumer of the callbacks above; expect knock-on warnings only. | C28 |
| `PhotographerJobViewModel.swift` | Clean: the detached worker (:316) captures `@Sendable` closure typealiases (:21–:23). | — |
| Models (`*Presentation`, `PhotographerJobModels`, `RemoteBackupModels`) | Clean: value types, many already `Sendable`. | — |
| `Platforms/*/…PlatformManager.swift`, `…FileSystemService.swift` | **Error:** `static let shared` of non-final classes; `IOSFileSystemService` is an `NSObject` subclass with `@MainActor` picker methods. | C12 (file access), C28 |
| `BitMatch/Core/Services/VolumeMonitorService.swift`, `UnreadableMediaMonitor.swift`, `DevModeManager.swift`, `GlobalErrorHandler.swift` (Mac) | Not analysed line by line. Hot spots: Disk Arbitration C callbacks with `Unmanaged` contexts hopping through `DispatchQueue.global()`/`.main` (VolumeMonitorService :89–:366), `static let shared` singletons, `Task.detached` in `DevModeManager` (:152). | C29 |

## 8. Guard tests and the bug that must make each fail

**E** = exists, **N** = new. "Plant" = a one-line production change that must turn the test red; plant once, confirm red, revert.

| # | Guards | Test | Plant |
|---|---|---|---|
| T1 | I1 | E `OperationOwnershipTests.testSecondOperationIsRejectedWhileFirstIsActive` | `ActiveOperationRegistry.reserve`: replace `guard activeID == nil else { return false }` with `activeID = nil`. |
| T2 | I2 | N `cancelBeforeAttachStillCancels`: drive `ActiveOperationRegistry` directly (`reserve`, `requestCancellation`, then `attach` a task) and assert the task is cancelled. The setup hook runs *after* `attach`, so it cannot reach this window; C01 therefore changes the registry from `private` to `internal` (the one production edit in Phase 1). | `ActiveOperationRegistry.attach`: delete `if shouldCancel { task.cancel() }`. |
| T3 | I3 | E `OperationOwnershipTests.testCancellationWaitsForVerifierCleanupBeforeOperationReturns` | In `executeOperation`'s catch, replace `await finishVerificationTasks(in: verifyTaskStore, cancelling: true)` with `_ = await verifyTaskStore.drain()`. |
| T4 | I4 | E `OperationOwnershipTests.testCancellationDuringDestinationSetupDoesNotFabricateFailureRows` | Delete the `catch is CancellationError { throw CancellationError() }` clause in destination setup. |
| T5 | I5 | E `SharedFileOperationsServiceTests.testStalePauseDoesNotBlockNextOperation` | Delete `await pauseState.resume()` at the top of `performFileOperation`. |
| T6 | I6 | N `operationReturnsOneVerifiedRowPerFile`: a pipelined Standard run returns exactly one row per (file, destination), each with a `verificationResult`, and the `onFileResult` stream's last row per key is the verify row. | `ResultStore.upsert`: replace `list[idx] = r` with `list.append(r)`. |
| T7 | I7 | N `verifyConcurrencyIsBounded`: a `ChecksumService` stub records its peak simultaneous `generateChecksum` calls over 50 files; assert ≤ `max(2, cores/2)`. | `AsyncSemaphore(count: …)`: change to `10_000`. |
| T8 | I8 | N `pauseStopsNewFileStarts`: 20 files; pause from the setup hook; wait 300 ms; the result set does not grow until `resumeOperation()`. | `PauseState.waitIfPaused` (later `PauseGate.wait`): make the body `return`. |
| T9 | I9 | N `pauseIsPerOperation`: two services; pause A mid-run; B must finish. **Expected to fail on `main`** (static `pauseCheck`). Land it with `withKnownIssue` (Swift Testing) or `XCTExpectFailure`; C07 removes the marker. Never skip it. | After C07: re-add a static hook that `readPinnedDestination` reads and `executeOperation` sets. |
| T10 | I10 | E `TransferFaultIntegrationTests.testInaccessibleDestinationReportsFailuresWhileOtherDestinationSucceeds`. If the plant does not turn it red (the unreadable root may fail per file rather than at pinning), add N `oneBadDestinationDoesNotAbortOthers` using the setup hook to throw `CocoaError(.fileWriteNoPermission)` for destination 0. | In destination setup's generic `catch`, replace `continue` with `throw error`. |
| T11 | Verification always hashes current bytes | N `sourceDigestIsNeverCached`: copy F to D1; rewrite F's bytes keeping size and mtime; copy F to fresh D2: must verify green. | In `FileCopyService.checksumVerification` (:777), `useCache: false` → `true`. (Before C05.) |
| T14 | Evidence bytes unchanged by the split | N `EvidenceGoldenTests`: fixed clock and rows; CSV, JSON (sorted keys) and checksum manifest compared with **inline string literals** captured from `main` before C03. Include one row per `ResultOutcome` and one project (photographer) case. | In `ReportExporter.escapeCSV`, remove the quote doubling. |
| T15 | Journal round-trips off the main actor | E `LocalTransferJournalTests` (all) + E `LocalTransferQueueIntegrationTests` | In `persist`, return before writing. |
| T16 | Source untouched through the pipeline | E `SourceTreeUnchangedTests` | After publishing in `copyFileSecurely`, `Darwin.utimes(source.path, nil)`. |
| T18 | exFAT publish never overwrites | E `ExFATDestinationTests` | In `publishByClaimingName`, drop `O_EXCL` from `flags`. |
| T19 | One verdict on every platform | E `PlatformVerdictParityTests` | In `CopyVerifyExecutor`'s verdict, drop `config.verificationMode != .quick`. |
| T20 | iOS Files-picker paths are user storage; `/private` alias | E `BitMatch-iPadTests/IOSStoragePathTests`, E `SafetyValidatorTests.testBackupInsideSourceIsFoundAcrossPrivateAlias` | Remove `"/private/var/mobile"` from `iOSUserStorageRoots`; make `comparableComponents` return the standardized components unchanged. |
| T21 | Backup-target rule | E `BackupTargetPolicyTests`, E `BackupTargetPolicyRealVolumeTests` | In `refusal`, return `nil` for `.restored`. |
| T22 | Typed outcome drives text and success | E `ResultOutcomeTests`, E `ResultStatusClassificationTests` | Make `ResultOutcome.isSuccess` return `true` for `.checksumMismatch`. |

(T12, T13 belonged to the project-store track, now §11; T17 guarded the deleted benchmark.)

## 9. Commits

Legend per step: **Files** moved/changed · **Access** changes · **Compiles** what must build · **Tests** what the Mac session runs · **Risk**. "Base" means `bash test.sh mac-test` + `bash test.sh ipad-build`.

### Phase 1 — guards (tests only)

- [ ] **C01 Test: engine guard tests (T2, T6, T7, T8, T9 as known issue, T10 if needed, T11).**
  Files: new `BitMatchTests/EngineGuardTests.swift` (reuse `TestHelpers/FakeFileSystemService.swift`, `DisposableTransferFixture`). Access: `ActiveOperationRegistry` `private` → `internal` (for T2). Compiles: both apps, tests. Tests: base; plant each §8 bug once and record red/green in the commit message. Risk: low; T8/T7 are timing-sensitive, so use the existing `WaitUntil` helper, never fixed sleeps as assertions.
- [ ] **C02 Test: evidence golden files (T14).**
  Files: new `BitMatchTests/EvidenceGoldenTests.swift` with inline literals produced by today's `ReportExporter.makeEnhancedCSV`, `makeEnhancedJSONReport` + `encodeEnhancedJSONReport`, `writeRecordedChecksumManifest`. Access: none. Tests: base. Risk: low. Capture the literals from the code on a Mac, not by hand.

### Phase 2 — remove crust and globals in place (no moves)

- [ ] **C03 Delete ReportExporter's unreachable UI paths.**
  Files: `ReportExporter.swift` — delete `showSavePanel`, `askToExportChecksums`, `exportChecksumsAsync` (and its `SharedChecksumService.shared` call), `exportIssuesOnly`, `showErrorAlert`, `showInfoAlert`, `generatePDFLegacy`, and imports left unused (`AppKit`/`UIKit`/`UniformTypeIdentifiers` if nothing else needs them). Keep `generatePDF` (Mac) until C15. Access: none. Compiles: both apps. Tests: base; T14 green. Risk: low; `grep -rn` for each name across all targets first (at `31bc940` none has a caller outside the file, and `generatePDFLegacy` is behind `macOS < 13` on a macOS 15.5 target).
- [ ] **C04 Delete ResultsOverflowService.**
  Files: delete `ResultsOverflowService.swift`, `BitMatchTests/ResultsOverflowUpsertTests.swift`; `CopyVerifyExecutor.swift` drops `maxResultsInMemory`, the service, `handleFileResult`'s `upsert` and `cleanupOverflowService`. Access: none. Tests: base (`CopyVerifyExecutorIntegrityTests`, `LiveResultsFeedTests`). Risk: low; nothing reads it (§ "What changed"). Needs Mike's nod (§12 Q1) only if he wants the spill-to-disk idea kept for later.
- [ ] **C05 Delete the checksum cache and `useCache`.**
  Files: delete `ChecksumCache.swift`, `ChecksumCache{,MD5,Invalidation}Tests.swift`; `ServiceProtocols.swift` (drop `useCache` from `ChecksumService` and the extension defaults that pass `true`); `SharedChecksumService.swift`; callers `ComparisonCoordinator:140`, `ReportExporter` (gone after C03), `RemoteBackupCoordinator:425`, `FileCopyService:777`, `BitMatch/Core/Services/SFTPRemoteBackupProvider.swift:140`; test stubs in `ExistingDestinationReuse`, `ComparePickerSelection`, `CopyVerifyExecutorIntegrity`, `OperationOwnership`, `SharedCompareFlow`, `LocalTransferQueueIntegration`, and call sites in `ChecksumTruncation`, `TransferFaultIntegration`, `TransferSoak`. Access: none. Tests: base; T11 green. Risk: low.
- [ ] **C06 PauseGate: event-driven pause.**
  Files: new `Shared/Core/Services/PauseGate.swift` (`final class PauseGate: Sendable`, `import Synchronization`, `Mutex` over paused flag + waiting continuations, cancellation-aware like `PermitQueue`); `SharedFileOperationsService.swift` replaces `PauseState` with a gate; the static hook is still set, now to `{ try await gate.wait() }`. Access: none. Tests: base; T5, T8 green. Risk: medium (continuation leaks on cancel; test cancel-while-paused).
- [ ] **C07 Thread the gate explicitly; delete the static `pauseCheck`.**
  Files: `ServiceProtocols.swift` (`pauseGate: PauseGate?` on the three `ChecksumService` methods), `SharedChecksumService.swift` (:187, :295, :340, :388), `FileCopyService.swift` (`verifyPinnedDestinationFile`, `canReuseExistingDestinationFile`, `readPinnedDestination` :821, `byteComparison` :855; `copyAllSafely` takes the gate instead of a closure), `SharedFileOperationsService.swift` (:347, :356 removed), every test stub from C05. Compare passes `nil` (no pause). Access: none. Tests: base; **T9 turns green, remove its known-issue marker**; T8. Risk: medium; one missed read site leaves a file unpausable (T8 catches the copy side, T9 the checksum side).
- [ ] **C08 Pipeline settings are inputs.**
  Files: `SharedFileOperationsService.swift` (init gains `pipelinedVerification: Bool = true`; :432 reads it), `Platforms/macOS/Services/MacOSPlatformManager.swift:19`, `Platforms/iOS/Services/IOSPlatformManager.swift` (read `DisablePipelinedVerify` there). Access: none. Tests: base. Risk: low.
- [ ] **C09 One free-space rule in the engine (behavior change, per decision).**
  Files: `SharedFileOperationsService.swift:414–426` — delete the estimate + 100 MB check; `SafetyValidator.performSafetyChecks` (manifest + 1 GB, the rule readiness shows) remains the only one. Tests: base (`ReadinessRuleTests`, `TransferReadinessTests`, `SharedFileOperationsEdgeCaseTests`); add N `insufficientSpaceUsesOneRule`. Risk: low; only differs when the caller's estimate exceeds the real manifest by more than 900 MB.
- [ ] **C10 Delete `_EnumeratorSource`; the manifest is required.**
  Files: `FileCopyService.swift` (:331 actor; `preEnumeratedFiles: [URL]` non-optional), tests `ExistingDestinationReuseTests:108`, `SharedFileOperationsEdgeCaseTests:309, :361, :440` pass `FileTreeEnumerator.enumerateRegularFiles(base:).map(\.url)`. Tests: base. Risk: low.
- [ ] **C11 Split ServiceProtocols: `FileAccess` for the engine.**
  Files: `ServiceProtocols.swift` (new `protocol FileAccess` = today's non-picker requirements, `getFileList` included so iOS keeps its scope-failure behavior; `FileSystemService: FileAccess` adds the four pickers); `SharedFileOperationsService` stores `any FileAccess`. Platform services and `FakeFileSystemService` conform unchanged. Tests: base. Risk: low.
- [ ] **C12 Sendable engine surface.**
  Files: `ServiceProtocols.swift` (`ChecksumService: Sendable`, `FileAccess: Sendable`, `FileOperationsService: Sendable`, `@Sendable` callbacks), `SharedChecksumService.swift` (`final`, `Sendable`), `SharedFileOperationsService.swift` (`final class …: Sendable`; all stored properties `let` and `Sendable`), `FileCopyService.swift` (`@Sendable` `onProgress`/`onError`), `CopyVerifyExecutor.swift` (closures now `@Sendable`; they already hop to the main actor), platform file services (`MacOSFileSystemService` final + `Sendable`; `IOSFileSystemService` `@unchecked Sendable` with a comment: its only mutable state is `currentDelegate`, touched only by the `@MainActor` picker methods), test stubs (`@unchecked Sendable` where they hold state). Access: none. Compiles: both apps in Swift 5 mode. Tests: base. Also, **locally only**, build with `SWIFT_STRICT_CONCURRENCY = complete` and record the warnings left in `File/*`, `SharedFileOperationsService`, `SharedChecksumService`, `ASCMHLGenerator`, `SafetyValidator`, `BackupTargetPolicy`: target zero. Risk: medium (wide but mechanical).

### Phase 3 — make the engine set closed (still one module)

- [ ] **C13 Move engine types out of mixed files.**
  Files: new `Shared/Engine/Models/{Verification,CameraLabelSettings,OperationProgress,Results,CompareCheckPlan,CompareStats}.swift` receiving `ChecksumAlgorithm`, `BitMatchError`, `VerificationResult`, `VerificationMode` (from `SharedModels.swift`), `CameraLabelSettings` (from `CameraModels.swift`), `OperationProgress`, `ProgressStage` (from `OperationModels.swift`), `ResultOutcome`, `ResultRow`, `ReportPrefs` (from `TransferModels.swift`), `CompareCheckPlan` (from `ComparePresentation.swift:17`), `CompareStats` (from `SharedAppCoordinator.swift:1424`); `git mv` `Logging/SharedLogger.swift` and `Extensions/URLExtension.swift` to `Shared/Engine/`. Code moves verbatim. Access: none. Compiles: trivially (same module). Tests: base. Risk: low.
- [ ] **C14 FolderComparer.**
  Files: new `Shared/Engine/FolderComparer.swift` (`struct FolderComparer: Sendable` over `any FileAccess` + `any ChecksumService`; body = today's `compareFolders`, `contentsMatch`, `buildFileMap`, `isFinderMetadata`, `isOffloadManifest`; cancellation = `Task.checkCancellation()`); `ComparisonCoordinator.swift` becomes a `@MainActor` wrapper that keeps `requestCancellation()`/`isCancellationRequested` and runs the comparer in a child task it cancels. Tests: base; `CompareIgnoredFilesTests`, `SharedCompareFlowTests`, `ComparePickerSelectionTests`, `CompareBlock` tests; `ipad-test`. Risk: medium; the Mac and iOS `getFileList` differ (iOS throws if its folder scope cannot start) and must keep being called through `FileAccess`.
- [ ] **C15 EvidenceWriter.**
  Files: new `Shared/Engine/Evidence/EvidenceWriter.swift` with the CSV/JSON/manifest/auto-save code, `EnhancedJSONReport`, `JSONReportItem`, `ReportExportError`, `reportFileName`, `verificationDescription`, `EvidenceKind`, `ProjectEvidence`; `ReportExporter.swift` (app) keeps `export(…)`'s signature for `CopyVerifyExecutor` and tests, builds `ProjectEvidence` from `PhotographerReportPayload`, renders the Mac PDF (`ReportSummary` + `ReportView`) and calls `EvidenceWriter.export(…, pdf:, appVersion:)`; `ASCMHLGenerator.generateInitialHistory` gains `toolVersion:` (app passes `CFBundleShortVersionString`). Access: none yet. Tests: base; **T14 byte-identical**, `PhotographerReportTests`, `ReportScannerTests`, `ReportEvidenceBytesTests`, `ASCMHLGeneratorTests`. Risk: medium; the JSON `photographyJob` box must encode exactly as the concrete type did.
- [ ] **C16 EvidenceReader.**
  Files: new `Shared/Engine/Evidence/EvidenceReader.swift` (today's `Snapshot` decode, size cap, skip list, `verificationMode(method:algorithm:)`, `isVerified`, `isReportFilename`, `isBitMatchNamed`, returning `ReportSnapshot`); `ReportScanner.swift` (app) maps snapshots to `TransferCard`. Tests: base; `ReportScannerTests`, `ReportScannerCancellationTests`, `MasterReportModelTests`. Risk: low.
- [ ] **C17 TransferCompletion and TransferJournal.** *(two commits: C17a, C17b)*
  - C17a Files: new `Shared/Engine/TransferCompletion.swift` (row mapping incl. `driveName(for:)`, the ASC MHL eligibility filter and detached write from `createASCMHLHistories`, the verdict rule and message from `handleSuccess` :270–:319 with the project gate as an input); `CopyVerifyExecutor.swift` calls it and keeps timing/error/state services, `IOSBackgroundTaskService`, `TransferKeepAwake` + `TransferSleepPreventing` (the keep-awake seam stays exactly where it is), the finalizer and notifications. Tests: base; T19, `CopyVerifyExecutorIntegrityTests` (keep-awake assertions), `ReportEvidenceBytesTests`, `CancelledOutcomeTests`. Risk: medium (verdict text must not change; T19 and the outcome presentation tests pin it).
  - C17b Files: new `Shared/Engine/TransferJournal.swift` (`final class TransferJournal: Sendable`, `Mutex<State>`, same sync API, file lock, atomic persist, bookmark resources, `LocalTransferRecord`/`State`/`Resource`/`Access`/`JournalError`); `LocalTransferJournal.swift` becomes the `@MainActor ObservableObject` wrapper that forwards each call and republishes `records`/`persistenceError`. Call sites in `SharedAppCoordinator` keep their shape. Tests: base; T15, `TransferLibraryPresentationTests`. Risk: medium (lock-file ownership in tests that make several journals).
- [ ] **C18 One path-containment rule (behavior change, safety-tightening).**
  Files: new `Shared/Engine/File/PathContainment.swift` with `31bc940`'s `comparableComponents`/`pathIsWithin` and a strict variant; `SafetyValidator.pathIsStrictlyWithin` (:560), `BackupTargetPolicy.isWithin` (:268) and `TransferReadiness`'s duplicate check (:66) use it. Tests: base, `ipad-test`; new cases for the `/private/var` alias in `BackupTargetPolicyTests` and `destinationRootIsContained`. Risk: low–medium; can only refuse more. Skip or defer if Mike prefers (§12 Q6).

### Phase 4 — the package

- [ ] **C19 Gather engine files under `Shared/Engine/`.**
  Files: `git mv` into `Shared/Engine/`: `File/{FileCopyService,SafetyValidator,BackupTargetPolicy,FileTreeEnumerator}.swift`, `SharedFileOperationsService.swift`, `SharedChecksumService.swift`, `AsyncSemaphore.swift`, `ASCMHLGenerator.swift`, `PauseGate.swift`, the engine half of `ServiceProtocols.swift` (split into `Shared/Engine/EngineProtocols.swift`), `Models/TransferReadiness.swift`, `Models/DestinationSelectionPolicy.swift`. Then run the closure check: the §2 script restricted to `Shared/Engine/**` must report no edge to a file outside it (and `grep -rE "import (SwiftUI|AppKit|UIKit|Combine)" Shared/Engine` must be empty). Access: none. Tests: base. Risk: low.
- [ ] **C20 Public surface, still in the app module.**
  Files: everything in `Shared/Engine/`: `public` on the §5 surface, explicit `Sendable` on public value types, explicit `public init`s (§4g.4), public default-argument helpers (§4g.3). `FileCopyService`/`PinnedDestination*`/`RunLedger`-to-be stay internal. Compiles: both apps (the compiler checks that public signatures only use public types). Tests: base. Risk: low here; misses show up in C21.
- [ ] **C21 Create `BitMatchEngine` and move the engine into it (Swift 5 mode).**
  Files: `Packages/BitMatchEngine/Package.swift` (`swift-tools-version: 6.0`, `platforms: [.macOS(.v15), .iOS(.v18)]`, one library + one target, `swiftLanguageModes: [.v5]`, `swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]`); `git mv Shared/Engine/* Packages/BitMatchEngine/Sources/BitMatchEngine/`; `BitMatch.xcodeproj/project.pbxproj` (an `XCLocalSwiftPackageReference` for `Packages/BitMatchEngine` in the project's `packageReferences`, an `XCSwiftPackageProductDependency` in `packageProductDependencies` of the `BitMatch` and `BitMatch-iPad` targets, and a Frameworks build-phase entry for each; do it in Xcode with *Add Package Dependencies… → Add Local…* and commit the diff); new `Shared/App/BitMatchEngineExports.swift` = `@_exported import BitMatchEngine`; add `@testable import BitMatchEngine` to tests that touch internals; add `public` wherever the build now fails. Compiles: both apps, `swift build --package-path Packages/BitMatchEngine`. Tests: base; `ipad-test`. Risk: **high** (pbxproj, module visibility for hosted tests, testability of a package module in Debug; see §13). If the test target cannot see the module, add the product to `BitMatchTests` too and make the library `type: .dynamic` so singletons are not duplicated.
- [ ] **C22 Engine tests into the package; `engine-test` job.**
  Files: `git mv` the tests that use only engine types (candidates: `ASCMHLGenerator`, `BackupTargetPolicy`, `BackupTargetPolicyRealVolume`, `CameraLabelSettings`, `ChecksumTruncation`, `DestinationSelectionPolicy`, `ExFATDestination`, `ExistingDestinationReuse`, `FileTreeEnumerator`, `LocalTransferJournal`, `ResultOutcome`, `ResultStatusClassification`, `SafetyValidator`, `SharedChecksum*`, `SharedFileOperations*`, `SourceTreeUnchanged`, `TransferFaultIntegration`, `TransferSoak`, `TransferReadiness`, `CompareIgnoredFiles`, `EngineGuard`, `EvidenceGolden`) to `Packages/BitMatchEngine/Tests/BitMatchEngineTests/`, with copies of `FakeFileSystemService`, `DisposableTransferFixture`, `TestFixtures`, `WaitUntil`, `FileOperationsTestLock`. Eleven of these use `MacOSFileSystemService.shared` (14 uses) or `MacOSPlatformManager.shared` (2): add an engine `LocalFileAccess` test helper equal to the Mac service's non-picker methods, or leave those tests in the app target. `IOSStoragePathTests` stays in `BitMatch-iPadTests`. `test.sh` gains `engine-test` (`swift test --package-path Packages/BitMatchEngine`); `ci.yml` runs it. Tests: base + `engine-test`; the moved-test count must equal the removed count. Risk: medium.
- [ ] **C23 Swift 6 language mode for the package.**
  Files: `Package.swift` (`swiftLanguageModes: [.v6]`); fix what is left (expected: little, after C07/C12/C17). Tests: base + `engine-test`. Risk: medium.

### Phase 5 — consolidate concurrency inside the package (§6)

- [ ] **C24 `Mutex` registry and `Atomic` copy index.** `ActiveOperationRegistry` → `Mutex`; `_ArraySource` → `Atomic<Int>` index into the manifest. Tests: T1–T4 + `engine-test` + base. Risk: low.
- [ ] **C25 `RunLedger`.** One actor per run replaces `ResultStore`, `VerifyCounter`, `DestinationProgress`, `ProgressState`; one ETA computation instead of four (or none: §12 Q2). Tests: T5, T6, `TransferProgressPresentationTests`, `engine-test`, base. Risk: medium.
- [ ] **C26 Structured verification; delete `AsyncSemaphore`.** One `withThrowingDiscardingTaskGroup` per destination, bounded hand-off (never `.bufferingOldest`, which drops jobs), in-flight cap `max(2, cores/2)`; delete `AsyncSemaphore.swift` and `ConcurrencyTests.swift`. Tests: T3, T6, T7, T8, `OperationOwnershipTests`, `TransferSoakTests`, `engine-test`, base. Risk: **high** (the core of the pipeline; keep the commit small and run the soak test several times).
- [ ] **C27 (optional) Thesis names.** One commit per rename, each with a deprecated `typealias` for one release: `SharedFileOperationsService` → `TransferPipeline`, `SharedChecksumService` → `ChecksumEngine`, `FileCopyService`+`PinnedDestinationDirectory` → `DestinationWriter`, `FileTreeEnumerator` → `CardSource`, `TransferJournal` stays. Risk: low.

### Phase 6 — the apps to Swift 6

- [ ] **C28 App targets: complete checking (Swift 5 mode), services and singletons.** `SWIFT_STRICT_CONCURRENCY = complete` on `BitMatch` and `BitMatch-iPad`; fix the §7 app rows marked C28 (camera singletons `Sendable`, `CameraMemoryService` lock, `SharedCameraDetectionService` final + `Sendable` results, platform managers final, `FolderRecipeRenderer` formatter). Tests: base, `ipad-test`. Risk: medium.
- [ ] **C29 App: platform lifecycle.** `OperationStateService` `asyncAfter` → `Task { @MainActor … }`, `IOSBackgroundTaskService` handlers and `Activity` updates, Mac `VolumeMonitorService` / `UnreadableMediaMonitor` Disk Arbitration callbacks, `DevModeManager`. Tests: base, `ipad-test`, plus a physical-device check of background time and Live Activity (simulator does not prove it). Risk: medium–high (runtime isolation traps with `MainActor.assumeIsolated`).
- [ ] **C30 `SWIFT_VERSION = 6.0`** on app and test targets. Tests: base, `ipad-test`, `engine-test`. Risk: medium.

## 10. Checklist: where each recent change is covered

| Item | Engine or app | Public API (engine) | Commit that moves or changes it | Swift 6 finding |
|---|---|---|---|---|
| **`ResultOutcome`** (typed outcome, `TransferModels.swift:74`) | Engine (value) | §5: `ResultOutcome`, `ResultRow.isSuccessStatus`, `FileOperationResult.outcome` | C13 (to `Shared/Engine/Models/Results.swift`), C20 public, C21 package | Clean; explicit `Sendable` already declared. Guards T22, T19. |
| **`BackupTargetPolicy`** | Engine (rule) | §5: `refusal`, `Origin`, `VolumeFacts`, `isSystemVolumeName`, `canonicalPath` | C18 (shared containment helper), C19 gather, C20 public (default args), C21 | Clean. Guard T21. |
| **`DestinationSelectionPolicy`** | Engine (rule; moves out of `Models/`) | §5: `evaluateBackup`, `evaluateSource`, `addBackups`, `Decision`, `ItemKind` + default helpers | C19 gather, C20 public, C21 | Clean; public default arguments (§4g.3). |
| **`TransferReadiness`** | Engine (rule; moves out of `Models/`) | §5: `assess`, `Status`, `requiredHeadroomBytes`, `isWritableFolder` | C18 (duplicate check uses shared helper), C19, C20, C21; C09 makes the engine enforce the same single 1 GB rule it shows | Clean. |
| **exFAT publish fallback** (`PinnedDestinationDirectory.publishTemporaryFile` → `publishByClaimingName`, `c1bc33f`) | Engine, internal | Not public: reached only through the pipeline; tested by package tests | C19 gather, C21 package, C22 (`ExFATDestinationTests` to package) | Clean: Darwin calls on immutable fds. Guard T18. |
| **`LiveProgressFeed` / `LiveResultsFeed`** | App (`@MainActor` observable feeds) | — (consume engine `OperationProgress` / `ResultRow` values) | Not moved. C04 removes the parallel overflow store; C25/C26 must keep I6 because `LiveResultsFeed.upsert` has no supersede rule | Clean (`@MainActor final class`). |
| **Keep-awake seam** (`TransferSleepPreventer.swift`, used by `CopyVerifyExecutor.swift:87, :135`) | App (lifecycle) | — | Stays with the app half of `CopyVerifyExecutor` in C17a, unchanged | Clean. `CopyVerifyExecutorIntegrityTests` keeps guarding begin/end. |
| **Estimate from speed** (`ProgressPresentationModel`; `DriveBenchmarkService`, `TransferEstimateModel` deleted in `ab7caf0`) | App (presentation) | — | Benchmark and estimate model: done, nothing to move. Engine ETA de-duplicated or dropped in C25 (§12 Q2) | `ProgressPresentationModel`: clean. |
| **SafetyValidator path normalization** (`31bc940`: iOS `/private/var/mobile` user storage, `/private` alias in `pathIsWithin`, `/etc`) | Engine | §5: `SafetyValidator` statics incl. `isProtectedSystemPath`, `folderOverlap` | C18 extends the same normalization to `pathIsStrictlyWithin` and `BackupTargetPolicy.isWithin`; C19–C21 move it; `IOSStoragePathTests` stays in the iPad test target | Clean. The `#if os(iOS)` branch compiles per platform in the package; only `ipad-test` exercises it. Guard T20. |
| **`AppCoordinator` gone (step 3)** | — | — | Nothing to do. The first draft's "after step 3 lands" gates are removed; `SharedAppCoordinator` is the only coordinator and the only caller of `CopyVerifyExecutor`, `ComparisonCoordinator`, `LocalTransferJournal` | — |

## 11. Out of scope for this plan

- **One project store (Core Data → JSON).** Still a promise-5 inconsistency (Mac: `CoreDataPhotographerJobStore` over `BitMatch.xcdatamodeld`; iPad/iPhone: `UserDefaultsPhotographerJobStore`). Independent of the package; if wanted, it builds on `TransferJournal`'s persistence (C17b) as a `JSONFileStore` with a one-time, non-destructive import and its own guard tests (import keeps every collection; import keeps pending profile deletions). §12 Q4.
- **One `@Observable` app model** (thesis target shape). After C30; not planned here.
- **PDF on iPad and iPhone** (THESIS Decision: later, low priority). C15 makes it a matter of passing `pdf: Data` from an iOS renderer.

## 12. Open questions for Mike

1. **`ResultsOverflowService`.** It is written and never read; `LiveResultsFeed` already holds every row in memory. Delete it (C04, recommended)?
2. **Engine ETA.** After the estimate-from-speed decision, `OperationProgress.timeRemaining` feeds only the iOS Live Activity. Drop it from the engine and feed the Live Activity from `ProgressPresentationModel`'s measured estimate (one estimator everywhere, recommended), or keep one copy in `RunLedger`?
3. **Made-up evidence numbers (promise 3).** The JSON report writes `peakSpeedMBps = average × 1.2` and `copyDuration = verifyDuration = duration × 0.5`; the CSV's per-file "Timestamp" is interpolated from the average rate. Replace them with measured values or remove the fields, as a separate commit after C15 that updates the golden files on purpose? (Recommended; it changes the report format, so `ReportScanner` compatibility must be checked.)
4. **Project store.** Keep the Core Data → JSON track (§11) on the list, or drop it?
5. **Camera detection.** Keep `CardLayoutClassifier` and the detectors in the app (recommended), or plan a second package target later?
6. **C18.** Apply one path-containment rule everywhere (can only refuse more), or leave `BackupTargetPolicy` and `pathIsStrictlyWithin` as they are?
7. **Imports.** Keep the `@_exported import BitMatchEngine` shim, or replace it with explicit imports in ~147 files after C21?

## 13. Compile risks and unverified claims

- Nothing in this plan was compiled or run; this environment has no Xcode. Every §7 row is a prediction; rows marked "possible" depend on SDK `Sendable` annotations (`DateFormatter`, ActivityKit `Activity`, `UIApplication.beginBackgroundTask`'s handler, whether the `DispatchQueue.main` special case covers `asyncAfter`).
- Not verified: that Xcode 16.4 builds a local package product into an app whose hosted unit-test bundle can `import`/`@testable import` it without also linking it; that `@_exported import` in one app file makes the module visible to every file of the app module and to `@testable import BitMatch` clients; and the exact pbxproj shape for a local package in an `objectVersion = 77` project.
- Not verified: `Synchronization.Mutex`/`Atomic` and `withThrowingDiscardingTaskGroup` compile in both app targets without extra settings (inferred from the deployment targets and Swift 6.1).
- Not verified: that `main` at `31bc940` itself builds and passes on a Mac. Several merged branches were written without Xcode (THESIS notes this for step 4.5), and `31bc940` says it still needs a real-device check.
- Not verified: T9 fails on `main` today; T10's plant turns the existing test red.
- The `ResultsOverflowService` and `ReportExporter` dead-code findings come from `grep` across all targets. A call through a protocol or `#selector` would not show up; none was found.
- The dependency graph matches type names across files; extensions, generic constraints and nested-type uses can hide edges. Every edge named in §2 was checked by hand; C19's closure check is the real test.
- The engine size after C19 is estimated at roughly 6,500–7,000 lines; not measured.
- Line numbers cite `31bc940` and will drift as the steps land; `cloud/tidy` edits some of the same files (`ProgressPresentationModel`, `SharedAppCoordinator`).
