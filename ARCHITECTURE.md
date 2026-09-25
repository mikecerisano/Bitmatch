# BitMatch Architecture

This document describes the code as it is today. It covers what exists and where it lives, not history or plans. For what BitMatch promises, and the plan for bringing the code in line with those promises, read [docs/THESIS.md](docs/THESIS.md).

Paths are relative to the repository root. Symbols are cited by type or function name rather than line number, because line numbers drift.

## Targets

`BitMatch.xcodeproj` defines six targets. None has Swift package dependencies. Every target is built in Swift 5 language mode, and the two app targets set `SWIFT_STRICT_CONCURRENCY = targeted`.

| Target | Product | Platform | Compiles |
|---|---|---|---|
| `BitMatch` | macOS app | macOS 15.5 | `BitMatch/`, `Shared/`, and one file from `Platforms/`: `Platforms/macOS/Services/MacOSPlatformManager.swift` |
| `BitMatch-iPad` | iPhone and iPad app (`TARGETED_DEVICE_FAMILY = 1,2`) | iOS 18.5 | `BitMatch-iPad/`, `Shared/`, `Platforms/`, and one item from `BitMatch/`: `BitMatch.xcdatamodeld` |
| `BitMatchTests` | unit tests hosted in `BitMatch.app` | macOS | `BitMatchTests/`, including `BitMatchTests/TestHelpers/` |
| `BitMatchUITests` | UI tests for `BitMatch` | macOS | `BitMatchUITests/` |
| `BitMatch-iPadTests` | unit tests hosted in `BitMatch-iPad.app` | iOS | `BitMatch-iPadTests/` |
| `BitMatch-iPadUITests` | UI tests for `BitMatch-iPad` | iOS | `BitMatch-iPadUITests/` |

Target membership comes from Xcode file-system synchronized folders (`PBXFileSystemSynchronizedRootGroup`). Each target lists the folders it compiles; there are no per-file build phase entries. Only two single files cross over, each through a membership exception in `project.pbxproj`:

- `MacOSPlatformManager.swift` is added to the Mac target. The iPad target also compiles all of `Platforms/`, but that file's body is inside `#if os(macOS)`, so it compiles to nothing on iOS.
- The Core Data model `BitMatch/BitMatch.xcdatamodeld` is added to the iPad target.

Test targets reach app code through `@testable import`. `test.sh` wraps the `xcodebuild` invocations for these jobs: `mac-test`, `mac-build`, `ipad-build`, `ipad-test` (which needs `IOS_SIMULATOR_DESTINATION`), and `release-builds`. `DEVELOPMENT.md` covers building and testing.

## Source layout

| Folder | Role | Built into |
|---|---|---|
| `Shared/Core/Models/` | Value types: operation state, progress, results, verification modes, camera, photographer and remote-backup models, and view-ready `*Presentation` types | Both apps |
| `Shared/Core/Services/` | The engine: copy, verify, safety, checksums, compare, ASC MHL, reports, journal/queue, camera detection, timing, errors, and `SharedAppCoordinator` | Both apps |
| `Shared/Core/ViewModels/` | `PhotographerJobViewModel` | Both apps |
| `Shared/Views/` | SwiftUI views used by both apps: `CompareResultsView`, `TransferLibraryView` | Both apps |
| `Platforms/iOS/Services/` | `IOSPlatformManager`, `IOSFileSystemService`, `IOSDriverScanner` | iOS app |
| `Platforms/macOS/Services/` | `MacOSPlatformManager` | Mac app (via the exception above) |
| `BitMatch/` | Mac app shell: `App/` (entry point, `ContentView`, `AppCoordinator`), view models, Mac-only services, and all Mac views | Mac app |
| `BitMatch-iPad/` | iPhone/iPad app shell: entry point, `ContentView`, and views | iOS app |

Some files under `Shared/` are wrapped in `#if os(...)` and so exist on only one platform. `RemoteBackupQueue.swift`, `RemoteBackupCoordinator.swift`, and `RemoteBackupProvider.swift` are macOS-only. `IOSBackgroundTaskService.swift` is real on iOS and a no-op stub on macOS.

## App shells

The two apps are separate SwiftUI shells over the shared engine. `CopyAndVerifyView`, `MasterReportView`, and the Compare screen are implemented separately in each shell.

### iPhone and iPad

- **Entry point.** `BitMatch-iPad/BitMatch_iPadApp.swift` registers the `com.bitmatch.app.transferprocessing` background-task handler and shows `ContentView`.
- **Coordinator.** `BitMatch-iPad/ContentView.swift` owns a `SharedAppCoordinator()` directly. Its iOS convenience initializer passes in `IOSPlatformManager.shared`.
- **Layout.** The layout is chosen by window width, not device idiom. `AdaptiveNavigationPolicy` in `Shared/Core/Models/AdaptiveNavigationPresentation.swift` returns one of:
  - `.compact` (under 600 pt): `BitMatch-iPad/Views/PhoneContentView.swift`
  - `.toolbar` (under 960 pt) or `.sidebar`: `BitMatch-iPad/Views/ModularContentView.swift`
- **Modes.** Both layouts switch on `coordinator.currentMode` (`AppMode`: Copy & Verify, Compare Folders, Master Report). They show `OperationProgressView` or `CompletionSummaryView` while an operation is running or finished.

### macOS

- **Entry point.** `BitMatch/App/BitMatchApp.swift` shows `BitMatch/App/ContentView.swift`. Menu commands (mode switching, Start, Cancel) are posted as `NotificationCenter` events.
- **Coordinator.** `ContentView` owns an `AppCoordinator` (`BitMatch/App/AppCoordinator.swift`). `AppCoordinator` wraps a `SharedAppCoordinator` built with `MacOSPlatformManager.shared`. It mirrors shared state into Mac-only view models in `BitMatch/Core/ViewModels/`: `ProgressViewModel`, `FileSelectionViewModel`, `CameraLabelViewModel`, and `SettingsViewModel`. It also owns a Core Data–backed `PhotographerJobViewModel`. Before a start, it copies view-model state into the shared coordinator and then calls `startOperation()` or `compareFolders()` on it.
- **Mac-only parts.** `AppCoordinator` owns the Mac-only pieces: the remote-backup (SFTP) scheduler and the Core Data photographer job store.

**Being consolidated (see the [docs/THESIS.md](docs/THESIS.md) plan):** the Mac `AppCoordinator` and the hand-mirroring into its view models.

## Operation state

**Being consolidated (see the [docs/THESIS.md](docs/THESIS.md) plan).** Today, state is tracked in two places:

- `SharedAppCoordinator.operationState` (`OperationState`, `Shared/Core/Models/OperationModels.swift`) is what the UI displays. The executor's `onStateChange` callback sets it.
- `OperationStateService` (`Shared/Core/Services/OperationStateService.swift`) tracks pause/resume capability and saved pause data. It routes transitions through `OperationStateMachine` (`Shared/Core/Services/OperationStateMachine.swift`), which can reject a transition.

`CopyVerifyExecutor` updates both, and `SharedAppCoordinator.pauseOperation()` / `resumeOperation()` read from `OperationStateService`.

## Copy → verify pipeline

The copy and verify path is the same on every platform:

```
SharedAppCoordinator.startOperation()
  → CopyVerifyExecutor.execute(config:callbacks:)
    → platformManager.fileOperations.performFileOperation(...)   // SharedFileOperationsService on both platforms
      → FileTreeEnumerator.enumerateRegularFiles                   // source manifest
      → SafetyValidator                                            // preflight
      → FileCopyService.copyAllSafely                              // per destination
      → FileCopyService.verifyPinnedDestinationFile                // per file, pipelined or sequential
    → ASCMHLGenerator.generateInitialHistory                       // optional, per destination
    → ReportExporter.export                                        // optional
```

### 1. SharedAppCoordinator (`Shared/Core/Services/SharedAppCoordinator.swift`)

`executeOperation(journalRecordID:)` runs these steps in order:

1. Requires a source and at least one destination.
2. Acquires platform access scopes for every selected URL.
3. Records the transfer in `LocalTransferJournal` (`enqueue`, then `markRunning`) before any copying. If this fails, the transfer does not start.
4. Runs `SafetyValidator.validateResolvedDestinationRoots`.
5. Builds a `CopyVerifyConfig` and calls the executor.
6. Afterwards, records the outcome in the journal with `finish`, `interrupt`, or `cancel`.

The executor's `onResult` and `onAuthoritativeResults` callbacks fill `results`. The final list replaces any rows streamed during the run.

### 2. CopyVerifyExecutor (`Shared/Core/Services/CopyVerifyExecutor.swift`)

`@MainActor`. It starts the services that run alongside the copy:

- `IOSBackgroundTaskService`: background task, idle timer, and Live Activity on iOS; a no-op stub on macOS
- `OperationTimingService`
- `ErrorReportingService`
- `OperationStateService`
- `ResultsOverflowService`: spills result rows to disk past 5,000 in memory and coalesces them to the latest row per file and destination

It then calls `performFileOperation`. On return, it:

1. Maps `FileOperation.results` into the authoritative `ResultRow` list.
2. Runs the optional photographer finalizer.
3. Writes ASC MHL histories, if enabled.
4. Exports the report, if enabled.

The completion is marked successful only if all of these hold:

- There is at least one result, and every row is a success status.
- Photographer finalization, if configured, persisted and certified the card as locally safe.
- No ASC MHL handoff issue occurred.
- The verification mode is not Quick.
- A requested report exported without error.

Any failure is appended to the completion message.

### 3. SharedFileOperationsService (`Shared/Core/Services/SharedFileOperationsService.swift`)

This is the only `FileOperationsService` implementation. Both platform managers create one around their `FileSystemService` and `SharedChecksumService.shared`. Only one operation can run at a time.

For each operation, in order:

1. **Access.** Starts access scopes, then checks `validateFileAccess` on the source and each destination.
2. **Manifest.** `FileTreeEnumerator.enumerateRegularFiles` (`Shared/Core/Services/File/FileTreeEnumerator.swift`) walks the source once:
   - Hidden files are included; symlinks and non-regular files are skipped.
   - Volume metadata folders at the root are skipped: `.Spotlight-V100`, `.fseventsd`, `.Trashes`, `.TemporaryItems`, and `.DocumentRevisions-V100`.
   - Any traversal error fails the operation.
3. **Preflight.** Runs `SafetyValidator` (`Shared/Core/Services/File/SafetyValidator.swift`):
   - `validateResolvedDestinationRoots`: final output roots (destination plus the camera-label or recipe subfolders) must be unique, must not overlap the source, must not be nested in each other, and must not be a file or a symlink.
   - `performSafetyChecks`: the source exists and is a folder; the source tree has no unsafe relative paths and no names that collide under case-insensitive or Unicode-normalized comparison; destination folders are unique and valid; there is enough free space.
   - A final free-space check requires each destination to hold the source size plus 100 MB.
4. **Per destination, in order:**
   - **Pin the root.** `PinnedDestinationDirectory.open` pins the output root by file descriptor, walking each component with `O_NOFOLLOW`. A safety-policy error aborts the whole operation. Any other error (for example, a disconnected drive) records every planned file as failed for that destination, and the operation moves on to the next destination.
   - **Copy.** `FileCopyService.copyAllSafely` copies using a worker count of `min(4, cores/2)`.
   - **Verify.** Unless the mode is Quick, verification is pipelined by default: each copied file queues a verify task. The concurrency limit is `max(2, cores/2)`, and at most 200 tasks can be queued. Setting the `DisablePipelinedVerify` user default switches to one sequential pass per destination instead.
5. **Results.** `ResultStore` keeps one current `FileOperationResult` per source/destination pair. The final `FileOperation` carries these results.

`pauseOperation()` / `resumeOperation()` toggle a flag that is checked between file chunks and between files. `cancelOperation()` cancels the running task.

### 4. FileCopyService (`Shared/Core/Services/File/FileCopyService.swift`)

- **Writes.** Every destination write happens relative to the pinned directory descriptor, never through a path that is resolved again. Each file:
  1. Is written to `.bitmatch.tmp.<UUID>`, created with `O_EXCL | O_NOFOLLOW`, in 4 MB chunks.
  2. Is synced to disk, and its size is checked against the source.
  3. Is checked for a source change during the copy (size, modification date, file identity).
  4. Gets the source modification date.
  5. Is published with `linkat` and then the temp file is removed. Publishing cannot replace a file that already exists.
- **Existing destination files.** An existing file is reused only if it matches the source size and every check for the verification mode (in Paranoid, the byte-by-byte comparison as well as SHA-256). Otherwise the file fails with a conflict and is never overwritten. In Quick mode, any existing file is a conflict.
- **Verification.** `verifyPinnedDestinationFile` reads the destination through the pinned descriptor. The source is hashed through the injected `ChecksumService` with `useCache: false`. The algorithms come from `VerificationMode.checksumTypes` (`Shared/Core/Models/SharedModels.swift`):

  | Mode | Verification | Existing-file reuse check |
  |---|---|---|
  | Quick | none (size only at copy time) | always a conflict |
  | Standard | SHA-256 | SHA-256 |
  | Thorough | SHA-256 + MD5 | SHA-256 + MD5 |
  | Paranoid | byte-by-byte comparison, plus SHA-256 (recorded for ASC MHL) | byte-by-byte comparison + SHA-256 |

### Checksums

- **`SharedChecksumService`** (`Shared/Core/Services/SharedChecksumService.swift`) does chunked MD5 (CryptoKit `Insecure.MD5`), SHA-1, and SHA-256, plus byte comparison.
- **`SharedChecksumCache`** (`Shared/Core/Services/ChecksumCache.swift`) is an actor-backed cache stored at `Caches/com.bitmatch.app/checksum_cache.json`. Entries last 1 hour, the cache holds at most 50,000 entries, and each key includes path, algorithm, size, modification time, and inode. The copy/verify path and Compare both bypass it (`useCache: false`).

## Compare

- **Entry point.** `SharedAppCoordinator.compareFolders()` calls `ComparisonCoordinator.compareFolders(left:right:verificationMode:onProgress:)` (`Shared/Core/Services/ComparisonCoordinator.swift`).
- **Callers.**
  - On Mac, `BitMatch/Views/CompareFoldersView.swift` starts it through `AppCoordinator.startOperation()`.
  - On iPhone and iPad, `ModularContentView` and `PhoneContentView` call the shared coordinator directly.
- **Enumeration.** Both sides go through `FileSystemService.getFileList`, which is `FileTreeEnumerator.enumerateRegularFiles` on both platforms. It uses the same hidden-file, symlink, and volume-metadata rules as the copy manifest. Files are matched by relative path.
- **Ignored files.**
  - `isFinderMetadata` ignores `.DS_Store`, `Icon\r`, and `._*` on both sides.
  - `isOffloadManifest` ignores a top-level `ascmhl/` folder and root-level `*.mhl` / `*.mhl.md5` files, but only when they appear on the destination side alone.
- **Comparison of common files.**
  1. Sizes are compared first; a size difference is a mismatch.
  2. If sizes are equal, content is checked according to the mode:
     - Quick: size only
     - Standard: SHA-256
     - Thorough: SHA-256 + MD5
     - Paranoid: byte-by-byte comparison
  - Files are processed one at a time, with `useCache: false`.
- **Result.** `CompareStats` (defined in `SharedAppCoordinator.swift`) holds counts and sorted path lists: only in source, only in destination, and mismatched. `isClean` is true only when all three are empty. The result is thrown away if the folders or mode change while the compare is running.
- **Display.** Both apps show the result in `Shared/Views/CompareResultsView.swift`. It lists up to 200 paths per group and exports JSON or CSV through `CompareReportDocument`.

## ASC MHL

`ASCMHLGenerator` (`Shared/Core/Services/ASCMHLGenerator.swift`) writes a first-generation ASC MHL v2.0 history into each destination's resolved output root.

- **When it runs.** Only from `CopyVerifyExecutor`, after results are authoritative and before the report. All of these must hold:
  - `generateASCMHL` is on. It is a `SharedAppCoordinator` property stored in the `BitMatchGenerateASCMHL` user default, on by default.
  - The mode is not Quick.
  - Every source file has a successful, valid SHA-256-verified row for that destination.

  If a destination fails these checks, it gets no history, and the transfer completes with issues.
- **Checks before writing.**
  - Refuses to extend or replace an existing history: an `ascmhl` folder in, above, or below the root is an error.
  - Rejects unsafe or duplicate paths and symlinks.
  - Re-reads each file through a pinned descriptor with `O_NOFOLLOW` and requires the SHA-256 to equal the transfer's verified SHA-256.
  - Refuses to write if the source and destination overlap.
- **Output.**
  - `ascmhl/0001_BitMatch_<UTC timestamp>Z.mhl`, with one MD5 hash per file.
  - `ascmhl/ascmhl_chain.xml`, which references the manifest by its C4 ID.

  Both files are written into a hidden staging folder, which is then renamed to `ascmhl` with `renameatx_np(..., RENAME_EXCL)`.
- **Reference check.**
  - `Scripts/ascmhl/validate_reference.sh` builds a fixture with `Scripts/ascmhl/GenerateFixture.swift`.
  - It then validates the output against the official ascmitc/mhl XSDs and CLI, confirms that CLI can append a second generation, and confirms that a corrupted file fails verification.

## Reports

- **`ReportExporter.export`** (`Shared/Core/Services/ReportExporter.swift`): the per-transfer report. `CopyVerifyExecutor` calls it when `ReportPrefs.makeReport` is on.
  - Location: `<first destination>/Reports/` for Copy & Verify.
  - Always written: CSV and JSON.
  - Written when the full report is on: a checksum `.txt` list, and a PDF rendered from `BitMatch/Views/ReportView.swift` on macOS only (iOS writes no PDF).
- **`SharedReportGenerationService`** (`Shared/Core/Services/SharedReportGenerationService.swift`): the Master Report PDF and JSON, built from scanned transfer reports.
  - Scanning: `Shared/Core/Services/ReportScanner.swift` on every platform (filenames, size limit, day, and what "verified" means). `DriveScanner` (Mac) and `IOSDriverScanner` (iOS) are thin entry points; each platform picks the folder its own way.
  - Saving: through a save panel on Mac, or shared from a temporary file on iOS.
- **Other exports.** Transfer history and the iOS completion summary export JSON/CSV through `TransferHistoryDocument` (`Shared/Views/TransferLibraryView.swift`).

## Transfer journal and queue

`LocalTransferJournal` (`Shared/Core/Services/LocalTransferJournal.swift`) is the durable transfer record on every platform.

- **Storage.**
  - A JSON array of `LocalTransferRecord` at `Application Support/BitMatch/transfer-history.json`.
  - Every change is written atomically before it is published.
  - An exclusive `flock` on `transfer-history.json.lock` prevents a second app instance from opening the journal.
- **Records.** Each record stores:
  - Source and destinations as `LocalTransferResource`: URL, bookmark, volume UUID, and resource ID
  - Verification mode, camera and report settings, the ASC MHL flag, and an optional project ID
  - State: `queued`, `running`, `interrupted`, `completed`, `issues`, or `cancelled`
  - The final `ResultRow`s
- **Outcomes.** `finish` records `issues` rather than `completed` for Quick mode, for an empty result list, or when any row is not a success.
- **Recovery.**
  - On load, any record still `running` becomes `interrupted`.
  - `requeue` creates a new record for a retry and keeps the old one.
  - `prepareToRun` resolves bookmarks and requires the same volume and resource identity as the original.
  - `reauthorize` lets the user reconnect a location, and rejects a different volume or folder.
- **The queue.** The journal also backs the local queue, driven by `SharedAppCoordinator`:
  - `startQueue()` / `stopQueueAfterCurrentTransfer()` start and stop it.
  - `processNextQueuedTransfer()` takes the oldest `queued` record with no project ID, loads its settings, and runs it through the same `executeOperation` path.
  - The queue stops when a transfer does not complete cleanly, and on cancel.
  - On iOS it runs only while the app is in the foreground; otherwise it pauses with a message.
- **UI.** Both apps show `Shared/Views/TransferLibraryView.swift` for queue, history, retry, reconnect, and export. Both shells show an interrupted-transfer banner.
- **Unrelated view.** `BitMatch/Views/CompactTransfer/TransferQueueView.swift` is not connected to this queue. Its queued and completed lists are local `@State`, filled only by a DEBUG helper.

### Remote backup queue (Mac only)

- **Components.** `RemoteBackupQueue`, `RemoteBackupCoordinator`, and `RemoteBackupProvider` are in `Shared/Core/Services/` but compile only on macOS. The SFTP implementation is `BitMatch/Core/Services/SFTPRemoteBackupProvider.swift`, which runs the system `ssh`, `sftp`, `ssh-keyscan`, and `ssh-keygen`. Credentials are stored in the Keychain (`BitMatch/Utilities/KeychainHelper.swift`).
- **Queue behavior.** Queue items and manifests persist through the photographer job store. The queue retries network errors with backoff, and never replaces an existing remote file.
- **Wiring.** `AppCoordinator` builds and schedules the queue.
- **On iOS.** `SharedAppCoordinator` always uses `UnavailableRemoteProjectCoordinator` (`Shared/Core/Services/ProjectRemoteCoordinator.swift`), which records the destination choice and throws `remoteUploadsRequireMac`.

### Photographer job stores

- **Protocol.** `PhotographerJobStore` is defined in `Shared/Core/Services/ProjectStoreProtocol.swift`.
- **iOS store.** iOS uses `UserDefaultsPhotographerJobStore` (`Shared/Core/Services/UserDefaultsPhotographerJobStore.swift`), which is the `SharedAppCoordinator` default.
- **Mac store.** Mac's `AppCoordinator` uses `CoreDataPhotographerJobStore` (`BitMatch/Core/Services/Photographer/PhotographerJobStore.swift`) on `BitMatchPersistenceController` (model `BitMatch/BitMatch.xcdatamodeld`).
- **Mac wiring detail.** The `SharedAppCoordinator` inside Mac's `AppCoordinator` still creates its own UserDefaults-backed `PhotographerJobViewModel`. The Core Data job reaches the transfer only through `photographerReportFinalizer`.

## Platform managers

`PlatformManager` (`Shared/Core/Services/ServiceProtocols.swift`) is the only platform seam the engine sees. It exposes:

- `fileSystem: FileSystemService`
- `checksum: ChecksumService`
- `fileOperations: FileOperationsService`
- `cameraDetection: CameraDetectionService`
- `supportsDragAndDrop`
- `presentAlert`, `presentError`, and `openURL`

| | `MacOSPlatformManager` (`Platforms/macOS/Services/`) | `IOSPlatformManager` (`Platforms/iOS/Services/`) |
|---|---|---|
| File system | `MacOSFileSystemService` (`BitMatch/Core/Services/Platform/`): `NSOpenPanel` pickers. `startAccessing` returns `true`, and `stopAccessing` does nothing. | `IOSFileSystemService`: `UIDocumentPickerViewController` folder picker (the delegate is retained). Uses security-scoped access at folder level, with per-file scopes for size and directory creation. |
| Checksum | `SharedChecksumService.shared` | `SharedChecksumService.shared` |
| File operations | `SharedFileOperationsService` | `SharedFileOperationsService` |
| Camera detection | `SharedCameraDetectionService` | `SharedCameraDetectionService` |
| Alerts | `NSAlert` (skipped under XCTest) | `UIAlertController` |
| Drag and drop | yes | no |

Both file system services list files through `FileTreeEnumerator`.

### Camera detection

- **One set of layout rules.** `CardLayoutClassifier` (`Shared/Core/Services/Camera/`) decides a card's brand from a bounded listing of its folder tree, brand-unique markers first. `CameraStructureDetector` (Mac auto-detect), the orchestrator and its folder-structure stage all use it, so they name the same brand.
- **Detection chain.** `SharedCameraDetectionService` first asks `CameraDetectionOrchestrator`. When the layout names a brand, the orchestrator only adds a model name, from that brand's reader (MEDIAPRO.XML, RAF header, ALE) or from Spotlight when it agrees with the brand. Otherwise it tries the remaining heuristic detectors in order and stops at the first match. A brand from the orchestrator is not overridden by the service's own folder-name and file-extension guesses. Names are cleaned by `CleanCameraNameService` on every platform.
- **Callers.** `SharedAppCoordinator` calls it when a source is chosen.
- **Mac-only callers.** `CameraNamingService`, `CameraMemoryService`, and `CameraStructureDetector` are in `Shared/`, but only Mac code calls them: `CameraLabelViewModel`, `FileSelectionViewModel`, and `CameraCardDetectionService`.

### Other Mac-only services (`BitMatch/Core/Services/`)

- `VolumeMonitorService` and `CameraCardDetectionService`: volume mount monitoring and card detection
- `DriveBenchmarkService`: read and write speed, used for time estimates
- `DriveScanner`: Mac entry point to the shared `ReportScanner` for Master Report scanning
- `DevModeManager`: DEBUG tools
- `GlobalErrorHandler`
- `AppLogger`: forwards to `SharedLogger`

## Tests

The `BitMatchTests` unit tests run on macOS against the shared engine through `@testable import BitMatch`. A single fake, `BitMatchTests/TestHelpers/FakeFileSystemService.swift`, stands in for `FileSystemService`.

| Area | Test files |
|---|---|
| Pipeline | `SharedFileOperations*Tests`, `CopyVerifyExecutorIntegrityTests`, `SafetyValidatorTests`, `SourceTreeUnchangedTests` |
| Journal and queue | `LocalTransferJournalTests`, `LocalTransferQueueIntegrationTests` |
| Compare | `SharedCompareFlowTests`, `CompareIgnoredFilesTests` |
| ASC MHL | `ASCMHLGeneratorTests` |
| Verdict parity across platforms | `PlatformVerdictParityTests` |
| Fault injection and soak | `TransferFaultIntegrationTests`, `TransferSoakTests` |

- **Scripted harnesses.** `Scripts/run_apfs_fault_tests.sh` and `Scripts/run_soak_tests.sh` drive the fault and soak tests. `docs/HARDWARE_TESTING.md` covers physical-device fault testing.
- **iOS tests.** `BitMatch-iPadTests` holds a small iOS suite.
