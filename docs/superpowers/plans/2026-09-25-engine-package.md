# Engine Package and Swift 6 Plan (Thesis Step 5)

> **For agentic workers:** This is a plan, not an implementation. Each stage ships on its own and ends green on `bash test.sh mac-test` and `bash test.sh ipad-build`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Move the parts of BitMatch that make promises 1–3 true (copy, verify, compare, checksums, ASC MHL, safety, journal, evidence) into a local Swift package, `BitMatchEngine`. The package builds in Swift 6 language mode from day one, has no UI imports, and is tested against real folders. The Mac, iPad and iPhone apps become thin clients of it (promise 5).

**Target shape (from `docs/THESIS.md`):** `CardSource`, `DestinationWriter`, `ChecksumEngine`, `TransferPipeline`, `TransferJournal`, `EvidenceWriter`, plus one `@Observable` app model whose verdict is computed from results.

**Method:** Everything below was worked out by reading the code on `main` at `08bae3f`. Nothing was compiled; the Swift 6 diagnostics in §6 are predictions. The dependency graph comes from a script that matches type names across files, and I checked every edge in it by hand.

## 0. Constraints and sequencing

- **Promises first.** No stage may change which bytes are read from the card, which files are written to a destination, or what a verdict says. Every stage lists the tests that guard this. Each test that claims to guard a behavior comes with a one-line production change that must make it fail (§9). Plant that bug once and check the test goes red before relying on it.
- **Files other sessions own.** Steps 2 and 3 are rewriting `SharedAppCoordinator.swift`, `OperationStateService.swift`, `OperationStateMachine.swift`, `CopyVerifyExecutor.swift`, `BitMatch/App/AppCoordinator.swift` and `CompletionVerdict*.swift`. Stages 1–2 below do not touch those files. Stages 3–6 do touch them, but only in small, named places (for example, moving `CompareStats` out of `SharedAppCoordinator.swift`), and they start only after steps 2 and 3 have merged.
- **Toolchain.** CI runs Xcode 16.4 (Swift 6.1). Deployment targets are iOS 18.5 and macOS 15.5, so `Synchronization.Mutex` and `withThrowingDiscardingTaskGroup` are available. Swift 6.2 features (`nonisolated(nonsending)`, default main-actor isolation) are **not** available and are not used here.
- **Project format.** `BitMatch.xcodeproj` uses file-system synchronized groups (`objectVersion = 77`). `Shared/` belongs to both app targets. `Platforms/` belongs to the iPad target, and the Mac target gets only `macOS/Services/MacOSPlatformManager.swift`. Moving a file out of `Shared/` removes it from both targets with no pbxproj edit. Adding the package does need one pbxproj edit (a local package reference plus a product dependency on each app target).
- **Tests.** 71 test files use `@testable import BitMatch`. Engine tests move to the package over time. Until then, app tests reach engine types through `import BitMatchEngine`, so those types must be `public`, not `internal`.

## 1. Inventory

`Shared/Core/Services` has 35 top-level files plus `Camera/` (12), `File/` (3) and `Logging/` (1). `Shared/Core/Models` has 15 files. Together that is about 18,200 lines.

| Concurrency and UI coupling | Files |
|---|---|
| `@MainActor` types | `ComparisonCoordinator`, `CopyVerifyExecutor`, `ErrorReportingService`, `FolderInfoService`, `IOSBackgroundTaskService`, `LocalTransferJournal`, `OperationStateMachine`, `OperationStateService`, `OperationTimingService`, `SharedAppCoordinator`, `SharedReportGenerationService`, `UserDefaultsPhotographerJobStore`, protocol `PhotographerJobStore`, protocol `ProjectRemoteCoordinator` |
| `ObservableObject` | the 10 `@MainActor` classes above that publish state |
| actors | `AsyncSemaphore`, `SharedChecksumCache`, `ResultsOverflowService`, `RemoteBackupQueue`; in `SharedFileOperationsService`: `ResultStore`, `VerifyCounter`, `DestinationProgress`, `ProgressState`, `VerifyTaskStore`, `PauseState`; in `FileCopyService`: `_EnumeratorSource`, `_ArraySource` |
| lock-guarded `@unchecked Sendable` | `ActiveOperationRegistry` (NSLock), `PermitQueue` (NSLock), `PinnedDestinationDirectory`, `PinnedDestinationFile` (immutable fd owners), `RemoteBackupArtifactLease` (NSLock); `CameraMemoryService` uses an NSLock but is not marked Sendable |
| `import SwiftUI` | `Models/SharedModels.swift` (for `DriveType.color`), `Services/ReportExporter.swift`, `Services/SharedAppCoordinator.swift` |
| `import AppKit` / `UIKit` | `ReportExporter`, `SharedReportGenerationService`, `OperationStateService`, `SharedAppCoordinator`, `IOSBackgroundTaskService` (iOS) |
| Other platform frameworks | `ActivityKit`, `BackgroundTasks`, `UserNotifications` (`IOSBackgroundTaskService`, `SharedAppCoordinator`); `AVFoundation` and `ImageIO` (camera detection); `Combine` (`FolderInfoService`, `LocalTransferJournal`, `OperationStateService`, `SharedAppCoordinator`) |
| `#if os(macOS)` whole-file | `RemoteBackupCoordinator`, `RemoteBackupProvider`, `RemoteBackupQueue` (SFTP, the explicit Mac exception) |
| Core Data | none in `Shared/`; `BitMatch/Core/Services/Photographer/{PhotographerJobStore,BitMatchPersistenceController}.swift` (Mac target only) |

## 2. Dependency graph

Arrows point to what a file uses. `SharedLogger` (`os.Logger`, portable) is used almost everywhere and is left out. Edges were verified by hand; the false positives the script reported for nested types named `Key`, `Entry` and `CodingKeys` were removed.

### 2a. Engine core (what moves)

```
SharedFileOperationsService ──► FileCopyService ──► PinnedDestinationDirectory/File (same file)
      │                             │  └──► SharedChecksumService.pauseCheck   ◄── static global (see §5)
      │                             └──► FileTreeEnumerator, SafetyValidator(FileOperationError), ChecksumService
      ├──► SafetyValidator ──► FileTreeEnumerator, CameraLabelSettings
      ├──► AsyncSemaphore
      ├──► ServiceProtocols (FileSystemService, ChecksumService, FileOperation, FileOperationResult)
      ├──► OperationProgress, VerificationMode, BitMatchError, CameraLabelSettings
      └──► UserDefaults.standard["DisablePipelinedVerify"]          ◄── app setting read inside the engine

SharedChecksumService ──► SharedChecksumCache (only when useCache == true; see §7c)
ComparisonCoordinator (@MainActor) ──► PlatformManager, RelativePathResolver, OperationProgress,
                                       CompareStats ◄── declared in SharedAppCoordinator.swift
ASCMHLGenerator ──► (nothing; CryptoKit, Darwin)
ResultsOverflowService ──► ResultRow
LocalTransferJournal (@MainActor ObservableObject) ──► VerificationMode, CameraLabelSettings, ReportPrefs, ResultRow
ReportExporter ──► ReportSummary ──► PhotographerReportPayload (PhotographerJobModels), AppMode
               ──► ReportView  ◄── BitMatch/Views/ReportView.swift (Mac target view)
               ──► NSSavePanel, NSAlert, ImageRenderer, NSHostingView, Bundle.main
               ──► SharedChecksumService.shared, ResultRow, ReportPrefs, PhotographerReportContext
```

### 2b. Orchestration (mixed; owned by steps 2 and 3 today)

```
CopyVerifyExecutor (@MainActor) ──► PlatformManager.fileOperations (engine)
    ├──► ResultsOverflowService, ReportExporter.export, ASCMHLGenerator, SafetyValidator   (engine)
    └──► OperationStateService, OperationTimingService, ErrorReportingService,
         IOSBackgroundTaskService, NotificationCenter(.operationCompleted)                  (app)
SharedAppCoordinator ──► everything above plus TransferHistoryDocument (Shared/Views),
                         PhotographerJobViewModel (Shared/Core/ViewModels), both PlatformManagers
```

### 2c. Features around the engine (stay in the app for now)

```
Camera/* (11 detectors) ──► CameraDetectionOrchestrator ──► SharedCameraDetectionService (AVFoundation)
CameraMemoryService (ImageIO, AVFoundation, UserDefaults), CameraNamingService, CameraStructureDetector
PhotographerJobModels ◄──► PhotographerCardAnalyzer, PhotographerJobPresentation (model → presentation inversion)
                      ──► RemoteBackupModels, ResultRow
RemoteBackup{Coordinator,Queue,Provider} (#if os(macOS)) ──► KeychainHelper (BitMatch/Utilities, Mac target)
FolderInfoService (@MainActor) ──► FolderInfo/EnhancedFolderInfo
```

### 2d. Who depends on the engine from outside

`SharedFileOperationsService` has 2 app users (the two `PlatformManager`s) and 10 test files. `SharedChecksumService` has 3 app users and 17 test files. `SafetyValidator` has 5 app users and 9 test files. `FileTreeEnumerator` has 3 app users and 5 test files. `ServiceProtocols` has 5 app users and 11 test files. There are few production call sites, so the move is mostly about tests and access control.

## 3. Classification

**E** = engine package. **A** = app. **S** = split the file. **D** = delete.

| File | Class | Notes |
|---|---|---|
| `File/FileCopyService.swift` | E | Pinned descriptors, atomic publish, no-overwrite reuse check. Becomes `DestinationWriter`. |
| `File/SafetyValidator.swift` | E | Becomes `SafetyPolicy`. |
| `File/FileTreeEnumerator.swift` | E | Becomes the core of `CardSource`. |
| `SharedFileOperationsService.swift` | E | Becomes `TransferPipeline` (§5). |
| `SharedChecksumService.swift` | E | Becomes `ChecksumEngine`. Remove the `static shared` and `static pauseCheck`. |
| `ChecksumCache.swift` | D | No production path reads it (§7c). |
| `AsyncSemaphore.swift` | D (after §5) | Replaced by a bounded task group. |
| `ASCMHLGenerator.swift` | E | Part of `EvidenceWriter`. |
| `ResultsOverflowService.swift` | E | Part of the run ledger or evidence path. |
| `LocalTransferJournal.swift` | S | Records, bookmarks and persistence go to the engine as `TransferJournal`. The `ObservableObject` wrapper stays in the app. |
| `ComparisonCoordinator.swift` | E | Becomes `FolderComparer`. Drop `@MainActor` and `PlatformManager`, and move `CompareStats` in. |
| `ReportExporter.swift` | S | CSV, JSON, checksum manifest and auto-save go to the engine as `EvidenceWriter`. PDF, `NSSavePanel`, `NSAlert` and issue export stay in the app. |
| `ServiceProtocols.swift` | S | `ChecksumService`, `FileOperation(Result)` go to the engine. `FileSystemService` pickers and `PlatformManager` stay in the app. |
| `Logging/SharedLogger.swift` | E | Duplicate or re-export it for the app. |
| `CopyVerifyExecutor.swift` | S (after step 2) | MHL handoff, report generation and overflow rows go to the engine. Background task, timing, state and error services stay in the app. |
| `OperationStateService`, `OperationStateMachine`, `OperationTimingService`, `ErrorReportingService`, `IOSBackgroundTaskService`, `FolderInfoService`, `SharedAppCoordinator` | A | UI state and platform lifecycle. |
| `SharedReportGenerationService.swift` | A | The Master Report (PDF drawing). Its JSON could later reuse `EvidenceWriter`. |
| `Camera/*`, `CameraMemoryService`, `CameraNamingService`, `CameraStructureDetector`, `SharedCameraDetectionService` | A | Naming and detection feed `DestinationLayout`. They make no safety promises. They could become a second package target later. |
| `Photographer*`, `FolderRecipeRenderer`, `ProjectStoreProtocol`, `ProjectRemoteCoordinator`, `UserDefaultsPhotographerJobStore` | A | Opt-in feature (promise 4). The engine gets its data as opaque evidence annotations (§4). |
| `RemoteBackup*` | A (Mac) | The SFTP exception. |
| `Models/SharedModels.swift` | S | Engine: `ChecksumAlgorithm`, `BitMatchError`, `VerificationResult`, `VerificationMode` (drop `estimatedTime`). App: `AppMode`, `FolderInfo`, `EnhancedFolderInfo`, `DriveType` (SwiftUI `Color`), `FolderDisplayInfo`, `Notification.Name`s. |
| `Models/CameraModels.swift` | S | Engine: `CameraLabelSettings`, `LabelPosition`, `Separator` (these decide the destination root, so they are a safety input). App: `CameraType`, `CameraCard`, `CameraDetectionResult`. |
| `Models/OperationModels.swift` | S | Engine: `OperationProgress`, `ProgressStage`. App: `OperationState`, `PauseInfo`, `CompletionState`, `VolumeEvent`. |
| `Models/TransferModels.swift` | S | Engine: `ResultRow`, `ReportPrefs`. App: `TransferCard`, `TransferMetadata`, `AutomaticSourceSelectionPolicy`. |
| `Models/ReportSummary.swift` | E | Replace `AppMode` with `EvidenceKind`, and `PhotographerReportPayload` with an annotation. |
| Every `*Presentation.swift`, `NotificationPermissionPolicy`, `AdaptiveNavigationPresentation` | A | Presentation. |
| `BitMatch/Core/Services/DriveBenchmarkService.swift` | D | See §8. |

## 4. What blocks the move

### 4a. UI and platform imports in engine files

1. `ReportExporter.swift`: `import SwiftUI`, `AppKit`/`UIKit`, `ImageRenderer(content: ReportView(...))`, `NSHostingView`, `NSSavePanel` (in `showSavePanel` and `exportIssuesOnly`), `NSAlert` (in `showErrorAlert` and `showInfoAlert`). `ReportView` lives in the Mac target, so the package cannot see it at all. **Fix:** the engine defines `public protocol ReportRenderer: Sendable { func pdf(summary: ReportSummary, rows: [ResultRow]) async -> Data? }`. The Mac app passes the existing `ImageRenderer` path. iOS passes `nil`, as it effectively does today (see §10, question 3). Save panels and alerts move to an app-side `ReportExportUI`.
2. `Models/SharedModels.swift`: `import SwiftUI` for `DriveType.color`. **Fix:** move `DriveType` to the app, or add the `color` in an app-side extension.
3. `ReportExporter.export` reads `Bundle.main.infoDictionary["CFBundleShortVersionString"]`. **Fix:** take `appVersion` as a parameter.
4. `SharedFileOperationsService` reads `UserDefaults.standard.bool(forKey: "DisablePipelinedVerify")`. **Fix:** put it in `PipelineConfiguration.pipelinedVerification`, which the app reads from defaults.

### 4b. `@MainActor` on engine types

1. `LocalTransferJournal` is `@MainActor final class … : ObservableObject` with `@Published records`. **Fix:** the engine gets `public final class TransferJournal: Sendable`, with state in a `Mutex<[TransferRecord]>` and the same **synchronous throwing** API (`enqueue`, `requeue`, `prepareToRun`, `markRunning`, `finish`, `interrupt`, `cancel`, `staleResourceIndexes`, `reauthorize`). Keeping the API synchronous means `SharedAppCoordinator`'s call sites keep their shape. The app wraps it in an `@Observable` or `ObservableObject` queue model that republishes `records` after each call.
2. `ComparisonCoordinator` is `@MainActor`, keeps `cancellationRequested` as main-actor state, and calls `platformManager.fileSystem` and `platformManager.checksum`. **Fix:** `public struct FolderComparer: Sendable` takes a `ChecksumEngine` and uses `FileTreeEnumerator` directly (both platform `getFileList` implementations already just call it). Security-scope start and stop move to a small `AccessScope` helper built on Foundation's `startAccessingSecurityScopedResource`, which works the same on both platforms. Cancellation uses the task's own cancellation; the app keeps its "was cancel requested" flag.
3. `ReportExporter.generatePDF` is `@MainActor`, and `exportChecksumsAsync` is `@MainActor`. Both move to the app with the renderer.
4. `CopyVerifyExecutor` is `@MainActor`, with `@MainActor` callbacks. It is an orchestrator, not the engine. After step 2, its engine half (`createASCMHLHistories`, `generateReport`, overflow collection) becomes `TransferPipeline` and `EvidenceWriter`. Its app half stays on the main actor.
5. The `PhotographerJobStore` protocol is `@MainActor`. It stays in the app.

### 4c. Core Data

There is none in `Shared/`, so Core Data does not block the package. It is still a promise-5 problem; §7 covers it.

### 4d. References from engine files to app code

| Reference | From | Fix |
|---|---|---|
| `CompareStats` (declared in `SharedAppCoordinator.swift`) | `ComparisonCoordinator` | Move it into the engine as `ComparisonResult`, or keep a typealias. Needs a one-line removal from `SharedAppCoordinator.swift` after step 3 lands. |
| `ReportView` (`BitMatch/Views`) | `ReportExporter` | `ReportRenderer` injection (§4a). |
| `PhotographerReportContext`, `PhotographerReportPayload` | `ReportExporter`, `ReportSummary` | The engine takes `EvidenceAnnotations { notes: String?, jsonSections: [String: Data] }`. The app encodes the photographer payload into a section with the same key, so the JSON report stays byte-identical. |
| `AppMode` | `ReportExporter`, `ReportSummary` | `public enum EvidenceKind { case copy, compare, master }`. |
| `KeychainHelper` | `RemoteBackup*` | Not engine code; no change needed. |

### 4e. Language and access-control blockers

1. **Implicit `Sendable` is lost.** Today every internal struct and enum whose members are `Sendable` is inferred `Sendable`. That is why `FileOperationResult`, `ResultRow` and `VerificationResult` can cross actors now. Public types do not get this inference. Each public engine value type must declare `Sendable` explicitly. `FileOperationResult.error: Error?` is fine (`Error` is `Sendable`).
2. **Existentials.** `any ChecksumService` and `FileSystemService` are captured into `Task {}` and `group.addTask {}` closures. The protocols must refine `Sendable`, or the engine must use concrete `Sendable` structs (recommended; see the API in §4f).
3. **Callbacks.** `FileOperationsService.ProgressCallback`, `FileResultCallback`, and `FileCopyService`'s `onProgress` and `onError` must become `@Sendable`, or be replaced by an `AsyncStream<TransferEvent>` (recommended).
4. **Tests use `@testable`.** The package exposes `public` API. Tests that poke internals (`PinnedDestinationDirectory.open`, `FileCopyService.copyAllSafely`) move into `Packages/BitMatchEngine/Tests` and use `@testable import BitMatchEngine` there.

### 4f. Proposed public API

The names follow the thesis. Stage 6 can first move the files under their current names with the minimum `public` surface, then rename in follow-up commits. Nothing here changes what gets copied or verified.

```swift
// Packages/BitMatchEngine/Sources/BitMatchEngine

// Inputs -------------------------------------------------------------
public struct TransferRequest: Sendable {
    public var source: URL
    public var destinations: [URL]
    public var verification: VerificationMode           // unchanged enum
    public var layout: DestinationLayout                // today: CameraLabelSettings
    public var evidence: EvidenceOptions                // today: ReportPrefs + generateASCMHL
}

public struct PipelineConfiguration: Sendable {
    public var copyWorkers: Int                         // today: min(4, max(1, cores/2))
    public var verifyConcurrency: Int                   // today: max(2, cores/2)
    public var maxVerifyInFlight: Int                   // today: 200 (VerifyTaskStore)
    public var pipelinedVerification: Bool              // today: !UserDefaults["DisablePipelinedVerify"]
    public var progressInterval: Duration               // today: 0.5 s
    public var destinationHeadroomBytes: Int64          // today: 100 MB
    public static let `default`: PipelineConfiguration
}

// Building blocks ----------------------------------------------------
public struct CardSource: Sendable {                   // FileTreeEnumerator + SafetyValidator source checks
    public static func scan(_ root: URL) throws -> CardSource   // fail-closed, read-only
    public let root: URL
    public let files: [FileEntry]                       // FileEntry made public
    public let totalBytes: Int64                        // overflow-checked
}

public final class DestinationWriter: Sendable {       // PinnedDestinationDirectory + FileCopyService
    public static func open(_ destination: URL, layout: DestinationLayout, source: CardSource) throws -> DestinationWriter
    public var logicalRoot: URL { get }                 // report metadata only
    func copy(_ file: FileEntry, from source: CardSource, gate: PauseGate,
              checksums: ChecksumEngine, mode: VerificationMode) async throws -> CopyOutcome
    func verify(_ file: FileEntry, mode: VerificationMode, checksums: ChecksumEngine,
                gate: PauseGate) async throws -> VerificationResult
}

public struct ChecksumEngine: Sendable {               // SharedChecksumService minus cache and statics
    public init()
    public func digest(of url: URL, _ algorithm: ChecksumAlgorithm, gate: PauseGate?) async throws -> String
    public func bytesEqual(_ a: URL, _ b: URL, gate: PauseGate?) async throws -> Bool
}

public final class PauseGate: Sendable {               // replaces PauseState + static pauseCheck
    public func pause(); public func resume()
    public func wait() async throws                     // returns at once when not paused; throws on cancel
}

// Pipeline -----------------------------------------------------------
public final class TransferPipeline: Sendable {
    public init(checksums: ChecksumEngine = .init(), configuration: PipelineConfiguration = .default,
                destinationSetupHook: (@Sendable (URL) throws -> Void)? = nil)   // keeps the test seam
    public func start(_ request: TransferRequest) throws -> TransferRun   // throws .operationAlreadyInProgress
}

public struct TransferRun: Sendable {
    public let events: AsyncStream<TransferEvent>
    public func pause(); public func resume(); public func cancel()
    public func outcome() async throws -> TransferOutcome
}

public enum TransferEvent: Sendable { case progress(OperationProgress), file(FileOutcome) }

public struct FileOutcome: Sendable, Codable, Hashable {
    public let relativePath: String
    public let destinationIndex: Int
    public let destinationPath: String
    public let size: Int64
    public let status: FileStatus                       // typed; see below
    public let checksums: [ChecksumAlgorithm: String]
    public let errorDescription: String?
}
public enum FileStatus: String, Sendable, Codable { case copied, verified, mismatch, failed }

public struct TransferOutcome: Sendable {
    public let request: TransferRequest
    public let started: Date, finished: Date
    public let files: [FileOutcome]
    public var allVerified: Bool { get }                // the single source for "green"
}

// Compare, journal, evidence -----------------------------------------
public struct FolderComparer: Sendable {
    public func compare(left: URL, right: URL, mode: VerificationMode,
                        progress: @Sendable (OperationProgress) -> Void) async throws -> ComparisonResult
}

public final class TransferJournal: Sendable { /* §4b.1 — same sync API as LocalTransferJournal */ }

public enum EvidenceWriter {
    public static func write(outcome: TransferOutcome, options: EvidenceOptions,
                             annotations: EvidenceAnnotations, appVersion: String,
                             renderer: (any ReportRenderer)?) async throws -> EvidenceReceipt
    public static func writeASCMHL(outcome: TransferOutcome, …) throws -> [String]
}
public enum SafetyPolicy { /* SafetyValidator's static API, unchanged */ }
```

**Typed status.** Today success is judged by matching strings on `ResultRow.status` (`"✅ Verified"`, `"⚠️ Checksum Mismatch"`, `"✅ Copied"`) in `ResultRow.isSuccessStatus`, and 12 call sites depend on that. `FileStatus` makes the verdict a property of data, not wording (promises 2 and 3). The migration keeps `ResultRow` and adds `ResultRow.init(_ outcome: FileOutcome)`, which produces exactly today's strings. The journal and report formats do not change. `ResultStatusClassificationTests` keeps the string classifier pinned until nothing else uses it.

## 5. Consolidating concurrency

### 5a. What exists today (per run)

| Tool | Where | What it protects | Hops per file |
|---|---|---|---|
| `ActiveOperationRegistry` (NSLock) | SFOS | one run per service instance; cancel before attach | 0 |
| `actor PauseState` | SFOS | the pause flag, **polled every 100 ms** by `Task.sleep` | 1–3 (per file, plus per chunk through the static) |
| `static SharedChecksumService.pauseCheck` | global | the pause hook for checksum and pinned reads | read per chunk |
| `actor ResultStore` | SFOS | result rows upserted by (src, dst) | 2 (copy and verify) |
| `actor VerifyCounter` | SFOS | verified count, used for progress and the "last" force-emit | 1 |
| `actor DestinationProgress` | SFOS | completed count per destination | 1–2 |
| `actor ProgressState` | SFOS | processed files and bytes, throttle clock, log cadence | 2–3 |
| `actor VerifyTaskStore` | SFOS | unstructured verify `Task`s, a 200-entry FIFO for backpressure | 1 |
| `AsyncSemaphore` actor + `PermitQueue` (NSLock) | shared | verify concurrency ≤ max(2, cores/2) | 2 |
| `actor _ArraySource` | FCS | the next-file index for copy workers | 1 |
| `actor _EnumeratorSource` | FCS | lazy enumeration. **Tests only**: production always passes `preEnumeratedFiles` | — |

With checksum verification that adds up to roughly 12–15 actor hops per file on a pipeline whose real work is disk I/O. The cost is small. The real problem is that nine separate state holders make the invariants hard to see. There is also one real hazard: the static `pauseCheck` is shared between all operations and all checksum callers. If a second `SharedFileOperationsService` or a compare checksums while a copy is paused, the second caller blocks on the first one's pause. When the first run ends and sets `pauseCheck = nil`, the second loses pausability.

### 5b. Target

1. **`PauseGate`** (`final class`, `Sendable`, `Mutex<State>` plus waiting continuations). `wait()` returns at once when not paused. When paused, it suspends on a continuation that `resume()` wakes, and it is cancellation-aware in the same way as the current `PermitQueue`. The gate is passed **explicitly** to the copy workers, the pinned reads and `ChecksumEngine`. This deletes `SharedChecksumService.pauseCheck` and the polling loop. The places that check for pause stay the same (the start of each copy file, each copy chunk, each checksum chunk, and each verify task).
2. **Run admission.** `TransferPipeline` keeps a `Mutex<RunSlot?>`, which is `ActiveOperationRegistry` with `NSLock` swapped for `Mutex`. It keeps the same semantics: cancellation never frees the slot, only the run's exit does, and a cancel that arrives before the task is attached is remembered.
3. **One `RunLedger` actor per run** replaces `ResultStore`, `VerifyCounter`, `DestinationProgress` and `ProgressState`. Its methods are `recordCopied(file:dest:size:) -> ProgressDecision`, `recordCopyFailed(...)`, `recordVerified(...) -> ProgressDecision`, `recordVerifyFailed(...)`, and `snapshot() -> [FileOutcome]`. A `ProgressDecision` carries either the next `OperationProgress` to emit or nothing, so the throttle, the "first or last always emits" rule and the ETA maths live in one place. The ETA code is currently copied three times, at `SharedFileOperationsService.swift:605`, `:669` and `:743`; this removes the duplication. Each file costs one hop per stage.
4. **Structured verification.** `VerifyTaskStore` plus `AsyncSemaphore` plus unstructured `Task {}` become one `withThrowingDiscardingTaskGroup` per destination. Copy workers hand verify jobs to it through an `AsyncStream` with a bounded buffer (`.bufferingOldest` is not acceptable because it drops jobs; use a hand-rolled bounded channel or keep a counter in the ledger and `await` a slot). The group caps in-flight verifies at `verifyConcurrency`. Cancelling the run cancels the group; leaving the group scope waits for every verify, which is today's `finishVerificationTasks`. This removes `AsyncSemaphore` from production. Delete it together with `ConcurrencyTests` only when nothing else uses it (`grep AsyncSemaphore` is currently limited to SFOS and tests).
5. **Copy workers.** Keep `withThrowingTaskGroup` with `copyWorkers` children. Replace `_ArraySource` with an `Atomic<Int>` index into the manifest array (`Synchronization.Atomic`, iOS 18 and macOS 15). Delete `_EnumeratorSource`, and pass the manifest in tests that use it (`SharedFileOperationsEdgeCaseTests` lines 309, 361, 440).
6. **Leave alone:** `PinnedDestinationDirectory` and `PinnedDestinationFile`. Their fds are immutable and closed only in `deinit`, so `@unchecked Sendable` is correct. Add a comment saying why. `RemoteBackupQueue` and `RemoteBackupArtifactLease` are app code and out of scope.

The result per run is one ledger actor, one gate, one mutex for admission, one atomic index and two task groups, with no unstructured tasks and no globals.

### 5c. Invariants the consolidation must keep (each has a test in §9)

- I1. A second `start` while a run is active throws `operationAlreadyInProgress`.
- I2. A cancel that arrives before the run task is attached still cancels it.
- I3. Cancelling waits for in-flight verifies to finish before `outcome()` throws. No verify outlives its run.
- I4. Cancelling during destination setup produces no failure rows.
- I5. A pause left over from a previous run does not block the next run.
- I6. A verify result replaces the copy row for the same (source, destination), whatever order they arrive in.
- I7. Verify concurrency never exceeds `verifyConcurrency`. The number of queued verify jobs stays bounded.
- I8. While paused, no new file starts copying and no checksum chunk is read.
- I9. Pausing one run does not pause another run or a folder compare.
- I10. An inaccessible destination produces failure rows for that destination only, and the other destinations still run.

## 6. What Swift 6 complete checking will flag, file by file

These are predictions from reading the code with Swift 6.1 semantics: SE-0414 region isolation; SE-0434, which makes global-actor-isolated closures `Sendable`; and no `nonisolated(nonsending)`. "Error" means an error in Swift 6 mode and a warning under `SWIFT_STRICT_CONCURRENCY=complete` in Swift 5 mode.

| File | Predicted diagnostics | Fix stage |
|---|---|---|
| `SharedChecksumService.swift` | **Error:** `static var pauseCheck` is nonisolated global mutable state. **Error:** `static let shared` has a non-`Sendable` type (non-final class). Possible errors where `@MainActor` callers send `self` into nonisolated async methods. | 1 |
| `SharedFileOperationsService.swift` | **Error:** `Task { try await executeOperation(...) }` captures non-`Sendable` `self` and the non-`@Sendable` `progressCallback` and `onFileResult`. **Error:** the verify `Task { [verifySemaphore] in … self … }` has the same captures. **Error:** `fileSystem: FileSystemService` and `checksumService: any ChecksumService` are non-`Sendable` and captured in escaping closures. **Warning:** writes to `SharedChecksumService.pauseCheck`. | 2 |
| `File/FileCopyService.swift` | **Error:** `group.addTask` captures `onProgress` and `onError` (escaping, not `@Sendable`) and `checksumService: any ChecksumService`. **Error:** it reads the static `SharedChecksumService.pauseCheck` (lines 761 and 795). `_EnumeratorSource` is clean (the non-`Sendable` enumerator is actor-held). | 2 |
| `ServiceProtocols.swift` | **Error**, knock-on: `FileOperationsService.ProgressCallback` and `FileResultCallback` are not `@Sendable`, and every conformer's escaping use fails. Probably a warning for redundant `nonisolated` on requirements of a non-isolated protocol. | 2 |
| `ChecksumCache.swift` | Clean (`actor`, `Task { [weak self] }`). Deleted in stage 1 anyway. | 1 |
| `AsyncSemaphore.swift` | Probably clean. `PermitQueue` is `@unchecked Sendable` behind a lock, and `withSemaphore` runs `operation` in the caller's isolation. | 2 (delete) |
| `ResultsOverflowService.swift` | Clean while `ResultRow` is internal. Once public, it needs `ResultRow: Sendable`. | 6 |
| `File/SafetyValidator.swift`, `File/FileTreeEnumerator.swift`, `ASCMHLGenerator.swift` | Clean. They are static functions over `Sendable` constants. | — |
| `LocalTransferJournal.swift` | Clean. It is `@MainActor`, which is exactly the problem (§4b.1). `LocalTransferAccess` needs `Sendable` once the pipeline holds it off the main actor. | 5 |
| `ComparisonCoordinator.swift` | **Likely error:** `@MainActor` code calls nonisolated async methods on `platformManager.checksum` and `.fileSystem`, which are non-`Sendable` existentials stored on a main-actor object ("sending … risks causing data races"). | 3 |
| `ReportExporter.swift` | **Error:** `showErrorAlert`, `showInfoAlert`, `exportIssuesOnly` and `showSavePanel` construct `NSAlert` and `NSSavePanel` (both `@MainActor`) from nonisolated `static` functions. `MainActor.run { generatePDF(summary:results:) }` needs `ReportSummary` and `[ResultRow]` to be `Sendable` (they are, implicitly, while internal). | 4 |
| `SharedReportGenerationService.swift` | Clean (`@MainActor`). App-side. | — |
| `CopyVerifyExecutor.swift` (hands off) | **Likely error:** `platformManager.fileOperations.performFileOperation(...)` sends a non-`Sendable` existential from the main actor. **Likely error:** `Task.detached` captures `reportSettings`, `reportResults` and `reportContext`, which need `Sendable`; they are implicit today. Whoever owns step 2 should know about these. | after step 2 |
| `OperationStateService.swift` (hands off) | **Likely error:** `NotificationCenter.addObserver(forName:object:queue:using:)` closures touch `@MainActor` state; they need `MainActor.assumeIsolated` or `Task { @MainActor in }`. `DispatchQueue.main.asyncAfter { [weak self] … }` is accepted in 6.1 but should become `Task`. | after step 2 |
| `IOSBackgroundTaskService.swift` | `Task { await act.update(content) }` sends `Activity` (non-`Sendable` before iOS 18 SDK annotations): **possible error**. The `BGTask` expiration handler touching main-actor state is a **likely error**. | 8 |
| `FolderInfoService.swift` | `Task.detached { [weak self] … }` inside a `@MainActor` class that calls `nonisolated` scanners. **Likely errors** where the detached closure reads `self` or returns non-`Sendable` `EnhancedFolderInfo` (implicit `Sendable` if its members are). | 8 |
| `Camera/*` (12 files), `CameraMemoryService` | **Error ×13:** `static let shared` of a non-`Sendable` `final class`. The detectors are stateless, so mark them `Sendable`. `CameraMemoryService` has mutable state under `NSLock`, so it needs `@unchecked Sendable` with a comment, or `Mutex`. | 8 |
| `CameraStructureDetector.swift` | `DispatchQueue.global().async { performDetection …; continuation.resume }`: fine if `performDetection` is static and pure. Probably clean. | — |
| `SharedCameraDetectionService.swift` | It returns `[String: Any]` across `async` boundaries (`analyzeFolderStructure`, `extractVideoMetadata`): **error** if called from another isolation (`Any` is not `Sendable`). | 8 |
| `FolderRecipeRenderer.swift` | `private static let dateFormatter: DateFormatter`: **possible error**, depending on SDK `Sendable` annotations for `DateFormatter`. | 8 |
| `RemoteBackupQueue.swift`, `RemoteBackupCoordinator.swift` | They already use `Sendable` heavily. Expect only knock-on errors where `PhotographerJobStore` (`@MainActor`) values cross into the actor. | 8 |
| Models (`*Presentation`, `PhotographerJobModels`, `RemoteBackupModels`) | Clean. They are value types, and several already declare `Sendable`. | 6 |
| `SharedAppCoordinator.swift` (hands off) | Unknown until step 3 lands. It is the largest consumer of the callbacks above. | after step 3 |

## 7. Core Data (jobs) vs. the JSON journal (transfers)

**Today** there are three persistence mechanisms for one product:

- Transfers: `LocalTransferJournal`, a JSON file in Application Support, atomic writes, with security-scoped bookmarks. The same on every platform.
- Photographer jobs, presets, SFTP profiles, remote manifests and queue items on **Mac**: `CoreDataPhotographerJobStore` over `BitMatch.xcdatamodeld` (3 model versions). Every entity is really `id + payload (JSON Data) + updatedAt`. The exception is `RemoteDestinationProfileRecord`, which also holds `credentialAccount` and a `pendingDeletion` flag used for a two-phase Keychain delete. There is also a dead `Item` entity. Core Data does no querying, has no relationships, and stores nothing that isn't already Codable.
- The same data on **iPad and iPhone**: `UserDefaultsPhotographerJobStore`, which keeps whole JSON arrays in `UserDefaults`. The Core Data model is explicitly excluded from the iPad target.

**Recommendation:** use one JSON-file store on every platform, built on the journal's persistence primitive.

1. Extract the journal's atomic write and read-validate code into an engine primitive, `JSONFileStore<Record: Codable & Identifiable & Sendable>` (a `Mutex`-guarded array with an atomic replace), and use it for `TransferJournal`.
2. Add `FileProjectStore: PhotographerJobStore` in the app, with one `JSONFileStore` per collection in `Application Support/BitMatch/Projects/`. Profiles store `credentialAccount` and `pendingDeletion` as fields, and the two-phase delete keeps its order: persist the marker, delete the Keychain item, then remove the record.
3. One-time import on first launch. On Mac, read the Core Data records (keep `BitMatchPersistenceController` only for this import). On iOS, read the `UserDefaults` keys. Write through `FileProjectStore`, then write a `migrated-v1` marker. **Do not delete the old store** for one release, so a downgrade still works. Retry pending profile deletions after the import.
4. After one release, delete `PhotographerJobStore.swift` (Core Data), `BitMatchPersistenceController.swift`, `BitMatch.xcdatamodeld`, `UserDefaultsPhotographerJobStore.swift` and the `whenAvailable` machinery.

Why: jobs and SFTP state would be stored the same way on every platform (promise 5). A job's history and a transfer's history become inspectable files a user can hand over (promise 3). The async store-load readiness path goes away, and so does `isAvailable`, which `AppCoordinator` and the SFTP scheduler currently wait on. Risk: the import is a data-loss surface, so it gets its own stage (7) and its own tests (§9, T12–T13). This work is independent of the package move and can happen before or after it. It must not be combined with step 3's Mac store injection.

## 8. DriveBenchmarkService

It is 273 lines, in the Mac target only, and its only caller is `AppCoordinator.updateTimeEstimate()`, which feeds `TransferPlanView`. The step-3 plan (`claude/retire-appcoordinator-plan`) currently proposes moving it into a Mac-only `TransferEstimateModel`.

**Recommendation:** delete it rather than port it or bring it into the engine.

- **It writes to destinations before anything has been validated.** `benchmarkWrite` writes a 10 MB `.bitmatch_benchmark_<UUID>` file into each selected destination root with a path-based `Data.write(options: .atomic)`. That write skips every protection the copy path has: no pinned descriptor, no symlink or traversal check, and no source-equals-destination or source-contains-destination check. It runs as soon as a destination is chosen, which is **before** `SafetyValidator` has seen the pair. If a user picks the card, or a folder on it, as a "backup", BitMatch writes 10 MB to the card and deletes it again. That breaks promise 1 ("the card is sacred") in spirit even when the delete succeeds, and in fact if the delete fails.
- The estimate model is also wrong for today's pipeline. It assumes destinations run one after another with a separate verify pass, it prices Paranoid as one read, and it ignores pipelined verification.
- The iPad and iPhone path already shows `operationReadinessAssessment.estimatedDuration`. One estimator on every platform is promise 5.
- Replacement: before the run, show the size-based estimate every platform already shows. During the run, `OperationProgress` already carries a measured `speed` and `timeRemaining`.

If Mike wants to keep a benchmark, the minimum fix is to make it **read-only** (source read speed only, which it already measures from an existing file), drop `benchmarkWrite` entirely, and run it only after `SafetyValidator.destinationSafetyIssue` returns nil for every pair.

## 9. Test guards and the bug that must make each fail

Each test either exists (**E**) or is new (**N**). "Plant" is the one-line production change that must turn the test red. The Mac session should plant each one once, confirm red, then revert.

| # | Guards | Test | Plant (must fail the test) |
|---|---|---|---|
| T1 | I1 | E `OperationOwnershipTests.testSecondOperationIsRejectedWhileFirstIsActive` | `ActiveOperationRegistry.reserve`: replace `guard activeID == nil else { return false }` with `activeID = nil` (always admit). |
| T2 | I2 | N `cancelBeforeAttachStillCancels`: call `cancelOperation()` from a `destinationSetupHook` while `performFileOperation` is between `reserve` and `attach`, and expect `CancellationError` | `ActiveOperationRegistry.attach`: delete `if shouldCancel { task.cancel() }`. |
| T3 | I3 | E `OperationOwnershipTests.testCancellationWaitsForVerifierCleanupBeforeOperationReturns` | `executeOperation` catch block: replace `await finishVerificationTasks(in: verifyTaskStore, cancelling: true)` with `_ = await verifyTaskStore.drain()`. |
| T4 | I4 | E `OperationOwnershipTests.testCancellationDuringDestinationSetupDoesNotFabricateFailureRows` | Delete the `catch is CancellationError { throw CancellationError() }` clause in the destination-setup `do/catch`, so it falls into the generic failure-row branch. |
| T5 | I5 | E `SharedFileOperationsServiceTests.testStalePauseDoesNotBlockNextOperation` | Delete `await pauseState.resume()` at the top of `performFileOperation`. |
| T6 | I6 | E `SharedFileOperationsEdgeCaseTests.testResultStoreRetainsLargeResultSetAndUpserts` covers the store itself. Add N `operationReturnsOneVerifiedRowPerFile`: a full pipelined Standard run returns exactly one row per (file, destination), each with a `verificationResult`. Today the order is guaranteed by construction, because the copy row is upserted before its verify task is created. `RunLedger` must keep that guarantee, or refuse to let a copy row replace a verify row, as `ResultsOverflowService.canReplace` does. | `ResultStore.upsert`: replace `list[idx] = r` with `list.append(r)`. |
| T7 | I7 | N `verifyConcurrencyIsBounded`: a `ChecksumService` stub that records its maximum number of simultaneous `generateChecksum` calls, 50 files, pipelined mode; assert max ≤ `max(2, cores/2)` | `let verifySemaphore = AsyncSemaphore(count: … )`: change to `count: 10_000`. |
| T8 | I8 | N `pauseStopsNewFileStarts`: 20 files, a `destinationSetupHook` pauses via `pauseOperation()`, wait 300 ms, and assert the set of result rows does not grow until `resumeOperation()` | `PauseState.waitIfPaused`: replace the body with `return`. |
| T9 | I9 | N `pauseIsPerOperation`: two `SharedFileOperationsService` instances; pause A mid-run; B must finish. **Expected to fail on `main` today** because of the static `pauseCheck`. Land it marked `withKnownIssue` (Swift Testing) or `XCTExpectFailure` (XCTest), and remove the marker with the stage-1 fix. Never skip it. | After the fix: put back a static hook that `FileCopyService.readPinnedDestination` reads (`if let p = SharedChecksumService.pauseCheck { try await p() }`) and have `executeOperation` set it. |
| T10 | I10 | E `TransferFaultIntegrationTests.testInaccessibleDestinationReportsFailuresWhileOtherDestinationSucceeds`. It makes the destination root unreadable, and I have not confirmed whether that fails at pinning (the setup `catch`) or per file. If the plant does not turn it red, add N `oneBadDestinationDoesNotAbortOthers`, which uses `destinationSetupHook` to throw `CocoaError(.fileWriteNoPermission)` for destination 0. | In the destination-setup generic `catch`, replace `continue` with `throw error`. |
| T11 | Verification always hashes current bytes (so deleting the cache changes nothing) | N `sourceDigestIsNeverCached`: run 1 copies and verifies file F to destination D1. Rewrite F's bytes, keeping its size and restoring its mtime. Run 2 copies F to a fresh D2 and must verify **green**, because the source digest is recomputed. | In `FileCopyService.checksumVerification`, change `useCache: false` to `useCache: true`. The stale cached source digest then mismatches D2, and run 2 goes red. |
| T12 | Store import keeps everything | N `FileProjectStoreImportTests.importsEveryCollection` (Core Data in-memory → JSON) | In the importer, drop the `presets` loop. |
| T13 | Two-phase profile delete survives import | N `importPreservesPendingProfileDeletion` | In the importer, map `pendingDeletion` to a hard-coded `false`. |
| T14 | Evidence is byte-identical across the `ReportExporter` split | N `evidenceWriterGoldenFiles`: fixed clock, fixed rows; CSV, JSON and checksum manifest compared with golden files captured from `main` **before** the split | In `ReportExporter.escapeCSV`, remove the quote doubling. |
| T15 | The journal round-trips off the main actor | E `LocalTransferJournalTests` (all) | In `LocalTransferJournal.persist`, return before writing. |
| T16 | The source is untouched through the whole pipeline | E `SourceTreeUnchangedTests` | In `FileCopyService.copyFileSecurely`, after publishing, `utimes` the **source** file (a one-line `Darwin.utimes(source.path, nil)`). |
| T17 | No benchmark file ever lands in a destination (only if the benchmark is kept) | N `benchmarkNeverWrites` | Restore `benchmarkWrite`. |

## 10. Stages

Each stage is one PR, green on `bash test.sh mac-test` and `bash test.sh ipad-build`.

**Stage 0: add guard tests (can start now; touches no hands-off file)**
- [ ] Add T2, T6, T7, T8, T9 (as a known issue), T10 if missing, T11, and T14 golden files captured from current `main`.
- [ ] Plant each bug from §9 and record red/green in the PR description.

**Stage 1: remove global state and dead paths inside the engine (no hands-off files)**
- [ ] Add a `pauseGate` parameter (optional, default `nil`) to `ChecksumService.generateChecksum` and `performByteComparison`, and to `FileCopyService.copyAllSafely` and `verifyPinnedDestinationFile`. Delete `SharedChecksumService.pauseCheck`. T9 turns green; remove its `withKnownIssue`.
- [ ] Delete `SharedChecksumCache` and the `useCache` parameter. Callers already pass `false`: `ComparisonCoordinator:100`, `ReportExporter:1044`, `RemoteBackupCoordinator:425`, `FileCopyService:717`, `SFTPRemoteBackupProvider:140`. Delete `ChecksumCache{,MD5,Invalidation}Tests.swift`, which test only the cache. Update the `useCache:` parameter in the `ChecksumService` test stubs (`ComparePickerSelection`, `CopyVerifyExecutorIntegrity`, `LocalTransferQueueIntegration`, `OperationOwnership`, `SharedCompareFlow`) and in the call sites in `ChecksumTruncation`, `TransferFaultIntegration` and `TransferSoak`.
- [ ] Delete `FileCopyService._EnumeratorSource`, make `preEnumeratedFiles` required, and update the 3 test call sites.
- [ ] Move `DisablePipelinedVerify` into an init parameter of `SharedFileOperationsService`, set by the two `PlatformManager`s.

**Stage 2: consolidate concurrency (§5)**
- [ ] `PauseGate`, `RunLedger`, a `Mutex` registry, an `Atomic` copy index, and structured verification. Delete `AsyncSemaphore` once unused.
- [ ] Make the engine callbacks `@Sendable`. Make `ChecksumService: Sendable` and `SharedChecksumService` a `final class`.
- [ ] Turn on `SWIFT_STRICT_CONCURRENCY = complete` **for a local build only** and record the warnings that are left in `Shared/Core/Services/{File/*,SharedFileOperationsService,SharedChecksumService,AsyncSemaphore}.swift`. The goal for this stage is zero.

**Stage 3: split mixed models; engine-side compare (after step 3 merges)**
- [ ] Split `SharedModels`, `CameraModels`, `OperationModels` and `TransferModels` along §3. This only moves code and changes no types. Files move from `Shared/Core/Models/` to `Shared/Engine/Models/` (still inside `Shared/`, so both targets keep compiling).
- [ ] Move `CompareStats` out of `SharedAppCoordinator.swift`. Turn `ComparisonCoordinator` into a nonisolated `FolderComparer` plus a thin `@MainActor` wrapper that keeps today's API for `SharedAppCoordinator`.

**Stage 4: split ReportExporter (T14 must stay green)**
- [ ] Create `EvidenceWriter` (engine) and `ReportExportUI` (app), and add the `ReportRenderer` protocol. Mac injects the `ReportView` renderer. Make `appVersion` a parameter. Pass the photographer payload as a JSON section with the same key.

**Stage 5: journal off the main actor**
- [ ] Create the `JSONFileStore` primitive and a `Sendable` `TransferJournal` with the same synchronous API. `LocalTransferJournal` becomes the app's observable wrapper. T15 must stay green.

**Stage 6: create the package (after step 2 has split `CopyVerifyExecutor`)**
- [ ] Add `Packages/BitMatchEngine/Package.swift` (`swift-tools-version: 6.0`, `platforms: [.macOS(.v15), .iOS(.v18)]`, language mode 6). Add the local package reference and product dependency to both app targets.
- [ ] Move `Shared/Engine/**` into `Sources/BitMatchEngine`. Mark the §4f surface `public` with explicit `Sendable`. Add `import BitMatchEngine` where needed.
- [ ] Move the pure engine tests (`SharedFileOperations*`, `SharedChecksum*`, `SafetyValidator*`, `FileTreeEnumerator*`, `ASCMHLGenerator*`, `SourceTreeUnchanged*`, `OperationOwnership*`, `TransferFault*`, `TransferSoak*`, `ResultsOverflow*`, `LocalTransferJournal*`, `CompareIgnoredFiles*`, `ResultStatusClassification*`) into `Tests/BitMatchEngineTests`. The shared `FileSystemService` fake moves with them. Add `swift test --package-path Packages/BitMatchEngine` to CI.
- [ ] Rename to the thesis names (`CardSource`, `DestinationWriter`, `ChecksumEngine`, `TransferPipeline`) in separate commits, with typealiases for one release.

**Stage 7: one project store (§7; independent, and must not be combined with step 3)**
- [ ] `FileProjectStore`, the importer, T12 and T13, keeping the old stores read-only for one release.

**Stage 8: app targets to Swift 6**
- [ ] Set `SWIFT_STRICT_CONCURRENCY = complete` on both app targets (Swift 5 mode), and fix §6's app-side rows. Then set `SWIFT_VERSION = 6.0`.
- [ ] Delete `DriveBenchmarkService` (§8), coordinating with the step-3 `TransferEstimateModel` task so that it reads the shared estimate instead.

## 11. Questions for Mike

1. **Quick mode and "green".** `ResultRow.isSuccessStatus` counts `"✅ Copied"` (size-only Quick mode) as success. Promise 2 says "success only when every file on every backup verified". Should Quick mode end amber ("copied, not verified") instead of green? This decides `TransferOutcome.allVerified`.
2. **Paranoid mode meaning.** `VerificationMode.paranoid.checksumTypes` is `[.sha256, .md5, .sha1]`, and the reuse check and compare use all three. The copy verify path (`verifyPinnedDestinationFile`) does a byte compare plus SHA-256 only. The UI copy says "adds a byte-by-byte comparison to checksum verification". Pick one definition before the engine API fixes it.
3. **PDF on iOS.** `ReportExporter` builds a PDF only on macOS (through `ReportView`), so iPad and iPhone evidence has no PDF. With a `ReportRenderer` hook, iOS could render the same SwiftUI view with `ImageRenderer`. Is that wanted for promise 5?
4. **Benchmark.** Delete it (recommended), or keep a read-only version (§8)?

## 12. Compile risks and unverified claims

- Nothing in this plan was compiled. Every §6 row is a prediction. The rows marked "likely" or "possible" depend on SDK `Sendable` annotations (for example `DateFormatter`, `ActivityKit.Activity`, `NSAlert`) that I could not check without Xcode.
- `withThrowingDiscardingTaskGroup` and `Synchronization.Mutex`/`Atomic` availability are inferred from the iOS 18.5 and macOS 15.5 deployment targets and Swift 6.1. I have not confirmed that CI's Xcode 16.4 SDK exposes them without extra imports (`import Synchronization`).
- The pbxproj edit for a local package, when the project uses synchronized groups, has not been tried in this repo.
- T9 is expected to fail on `main`. I have not demonstrated it.
- The dependency graph was built by matching type names across all `.swift` files. Extensions and generic constraints may hide a few edges. I checked all the edges named in §2 by hand.
- Line numbers cite `main` at `08bae3f` and will drift once steps 2 and 3 land.
