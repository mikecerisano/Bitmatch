# BitMatch Architecture Documentation

## Overview

BitMatch keeps one copy-and-verify operation path in the shared core. macOS and
iPad provide their own pickers, security/access integration, and SwiftUI views;
both platforms hand the resolved operation to the same executor and file
services. This keeps safety decisions and result semantics out of platform UI.

## Core Design Principles

### 1. Shared Business Logic
All core functionality is implemented in shared services that both platforms can use:
- File operations and verification
- Camera detection and labeling
- Report generation
- Operation state management

### 2. Platform Abstraction
Platform-specific implementations are hidden behind protocols:
- `FileSystemService` - File system operations
- `PlatformManager` - Platform-specific UI and system integration

### 3. Reactive State Management
Uses SwiftUI's `@Published` and `@ObservedObject` for reactive UI updates:
- `SharedAppCoordinator` manages global application state
- Views automatically update when state changes

## Key Components

### SharedAppCoordinator
**Location**: `Shared/Core/Services/SharedAppCoordinator.swift`

The central coordinator that manages application state and orchestrates operations:

```swift
class SharedAppCoordinator: ObservableObject {
    // Core state
    @Published var sourceURL: URL?
    @Published var destinationURLs: [URL] = []
    @Published var operationState: OperationState = .idle
    @Published var progress: OperationProgress?
    
    // Platform abstraction
    let platformManager: PlatformManager
    
    // Core operations
    func startOperation() async
    func selectSourceFolder() async
    func addDestinationFolder() async
}
```

### Shared Copy-and-Verify Path

`SharedAppCoordinator` prepares `CopyVerifyConfig` and delegates execution to
`CopyVerifyExecutor`. The executor owns operation timing, state, error
tracking, iPad background-task handling, result overflow, and report handoff.
It calls `PlatformManager.fileOperations.performFileOperation(...)`, which is
implemented by `SharedFileOperationsService` on both platforms.

The shared service acquires access scopes, checks source and destination access,
runs `SafetyValidator`, enumerates the source, copies with bounded concurrency,
and records one current result per source/destination pair. Verification can
run in a bounded pipeline. The executor maps progress and rows back to each
platform UI, then seals completion state and generates enabled reports. A view
can explain readiness, but it cannot bypass this shared preflight.

### Platform Managers

#### macOS: MacOSPlatformManager
- Native macOS file dialogs
- Menu bar integration
- Window management
- macOS-specific file system operations

#### iOS: IOSPlatformManager
- UIDocumentPickerViewController integration
- iOS security-scoped resource management
- Touch-optimized interactions
- iOS-specific permissions handling

### Shared Services at a Glance

- `SharedFileOperationsService`
  - Copy to multiple destinations, pause/resume, progress callbacks
  - Verification: checksum or byte‑by‑byte (paranoid)
- `FileCopyService`
  - Temp-file copy, flush, source-stability check, destination conflict checks, and final promotion
  - Reuses existing destination files only when they are proven identical
- `SafetyValidator`
  - Preflight source/destination containment, duplicate roots, symlinked output roots, unsafe relative paths, and case/Unicode-normalized collisions
- `SharedChecksumCache`
  - Actor‑based persistent cache (1h TTL) keyed by path + algorithm + file size + modification time
  - Disk‑backed (Caches/com.bitmatch.app), reduces re‑verification time by orders of magnitude
- `SharedChecksumService`
  - MD5, SHA‑1, SHA‑256 (chunked hashing with progress)
  - Byte compare for parity checks
  - MD5 is provided via CryptoKit’s `Insecure.MD5` for legacy compatibility; SHA‑256 is recommended for integrity verification
- `OperationTimingService`
  - Tracks elapsed time, rolling/average/peak speeds, ETA (bytes‑based)
- `OperationStateService`
  - Pause/resume lifecycle, minimal persistence, system notifications (iOS/macos)
- `ErrorReportingService`
  - Collects errors/warnings, summarizes, exports textual report
- `SharedReportGenerationService`
  - Generates professional PDF and JSON reports (cross‑platform rendering helpers)
- `ResultsOverflowService`
  - Spills very large result sets to disk while preserving latest per-file/per-destination status for reports

### File System Services

#### FileSystemService Protocol
```swift
protocol FileSystemService {
    func selectSourceFolder() async -> URL?
    func selectDestinationFolders() async -> [URL]
    func validateFileAccess(url: URL) async -> Bool
    func getFileList(from folderURL: URL) async throws -> [URL]
    nonisolated func getFileSize(for url: URL) throws -> Int64
    nonisolated func createDirectory(at url: URL) throws
    nonisolated func freeSpace(at url: URL) -> Int64
}
```

#### Platform Implementations
- **IOSFileSystemService**: Handles iOS security-scoped resources and document picker
- **MacOSFileSystemService**: Handles macOS file dialogs and direct file system access

## Data Models

### Core Models (`Shared/Core/Models/`)

#### SharedModels.swift
- `FolderInfo`: Basic folder metadata
- `EnhancedFolderInfo`: Extended folder analysis
- `VerificationResult`: File verification outcomes
- `AppMode`: Application operation modes
- `VerificationMode`: Different verification strategies

#### CameraModels.swift
- `CameraType`: Supported camera types and detection
- `CameraCard`: Detected camera card information
- `CameraLabelSettings`: Folder naming configuration

#### OperationModels.swift
- `OperationState`: Current operation status
- `OperationProgress`: Real-time progress tracking
- `CompletionState`: Operation completion status
 - `PauseInfo`: Codable pause snapshot for persistence

#### TransferModels.swift
- `TransferCard`: Individual transfer records
- `TransferMetadata`: Transfer operation metadata
- `ResultRow`: Report row data
- `ReportPrefs`: Report generation settings

## UI Architecture

### macOS Interface
**Primary View**: `BitMatch/App/ContentView.swift`

Features:
- Dynamic window sizing based on content
- Mode-specific layouts
- Transfer-plan cards show source, destinations, options, and preflight status before transfer
- Integrated report panel
- Professional desktop interactions

Key Components:
- `CopyAndVerifyView`: File transfer interface
- `CompareFoldersView`: Folder comparison interface
- `MasterReportView`: Report generation interface
- `ReportSettingsPanel`: Report configuration

### iPad Interface
**Primary View**: `BitMatch-iPad/Views/ModularContentView.swift`

Features:
- Touch-optimized layouts
- Collapsible sections
- Professional card designs
- Native iOS interactions
- The same transfer-plan presentation shows setup, readiness, warnings, and blocked states before transfer

Key Components:
- `CopyAndVerifyView`: Enhanced touch interface with collapsible sections
- `CompareFoldersView`: Side-by-side folder selection
- `MasterReportView`: Volume scanning and report generation
- `OperationProgressView`: Real-time progress display
- `CompletionSummaryView`: Operation completion interface

## Flow Diagrams

### Copy & Verify (shared operation path)

1. macOS or iPad selection UI sets source and destination URLs; its transfer-plan UI renders setup, readiness, warnings, or blockers.
2. User taps Start → the coordinator builds `CopyVerifyConfig` and runs readiness checks against the resolved final output roots.
3. `CopyVerifyExecutor` starts services:
   - `OperationTimingService.startOperation(...)`
   - `OperationStateService.startOperation(...)`
   - `ErrorReportingService.startErrorTracking(...)`
4. `CopyVerifyExecutor` invokes `PlatformManager.fileOperations.performFileOperation(...)`; both platforms reach `SharedFileOperationsService`.
5. `SharedFileOperationsService` performs core preflight:
   - source exists and is a directory
   - destinations are unique and writable
   - final destination roots are unique, non-nested, non-symlinked folders
   - source tree has no unsafe relative paths or portable-name collisions
6. `FileCopyService.copyAllSafely(...)` copies each file with temp-then-promote semantics and per-file error reporting.
7. Verification runs inline or in a bounded pipeline, depending on mode.
8. Progress and per-file rows flow through the executor to timing, state, and platform UI.
9. On completion, the executor coalesces current result rows, finalizes state, and invokes `SharedReportGenerationService` when reports are enabled.

### Compare Folders (basic)

1. UI sets `leftURL` and `rightURL`
2. Coordinator `compareFolders()` enumerates both via `FileSystemService.getFileList` (includes hidden files, skips symlink entries)
3. Computes set differences (only in source/destination, common)
4. Future extension: checksum/path parity for deeper comparisons

## Platform Notes

### iOS Security‑Scoped URLs
The iOS file system service acquires a folder‑level security scope for enumeration, and only falls back to per‑file scopes on errors, using `startAccessingSecurityScopedResource()` with `defer` cleanup. See `IOSFileSystemService` for the pattern and delegate retention in the document picker.

### macOS Manager (legacy target)
The legacy Mac target includes a shim `MacOSPlatformManager` under `BitMatch/Core/Services/Platform` so it can build without the `Platforms/` group; the modern manager lives under `Platforms/macOS` and is used by the shared coordinator in the macOS build. The shim initializes UI‑facing services on the main actor to respect Swift’s actor isolation rules.

## State Flow

### Typical Operation Flow
1. **Folder Selection**: User selects source folder
   - Platform-specific picker presented
   - `SharedAppCoordinator.sourceURL` updated
   - UI automatically refreshes via `@Published`

2. **Folder Analysis**: Selected folder is analyzed
   - `EnhancedFolderInfo` generated asynchronously
   - Camera detection performed
   - UI updates show folder details

3. **Destination Setup**: User adds backup destinations
   - Multiple destinations supported
   - Each destination validated for access and space

4. **Operation Configuration**: User configures operation
   - Verification mode selection
   - Camera labeling settings
   - Report generation options

5. **Operation Execution**: File transfer begins
   - `OperationState` changes to `.inProgress`
   - Real-time progress updates via `OperationProgress`
   - UI switches to progress view

6. **Completion**: Operation finishes
   - `OperationState` changes to `.completed`
   - Results displayed in completion view
   - Reports generated if configured

## Error Handling

### BitMatchError Enum
Comprehensive error types for user-friendly error messages:
- `fileAccessDenied`: Permission issues
- `fileNotFound`: Missing files during operation
- `checksumMismatch`: Verification failures
- `insufficientStorage`: Space limitations
- `operationCancelled`: User cancellation

### Platform-Specific Errors
- **iOS**: Security-scoped resource access failures
- **macOS**: File system permission issues

## Performance Considerations

### Async/Await Usage
All file operations use Swift concurrency to prevent UI blocking. Heavy filesystem work is dispatched off the main actor and parallelized conservatively:
```swift
// Example: background folder stats + batched parallel fan‑out
let info = await Task.detached(priority: .userInitiated) { computeInfo(url) }.value
await withTaskGroup(of: Result.self) { group in /* cap concurrency */ }
```

### Memory Management
- Security-scoped resources properly managed with defer blocks
- Large file lists processed incrementally where possible
- Final operation results are indexed and retained for accurate completion/reporting; UI result overflow can spill to disk for large transfers
- Progress updates throttled to prevent UI spam

### Background Processing
- File operations run on background queues; folder enumeration off-main
- UI updates dispatched to main queue; progress throttled for smoothness
- Cancellable operations for user responsiveness; pause/resume supported

## Testing Strategy

### Unit Testing
- Core business logic in shared services
- Mock platform managers for testing
- Isolated component testing
- Safety regressions for destination conflicts, hidden files, empty folders, source mutation, portable path collisions, paranoid byte comparison, and large result retention

### Integration Testing
- Full operation flows
- Platform-specific implementations
- Error condition handling

### UI Testing
- User interaction flows
- State management verification
- Platform-specific behavior validation

### Concurrency and Fault Diagnostics

`BitMatchTests/ConcurrencyTests.swift` targets the shared `AsyncSemaphore`:
basic permit behavior, bounded concurrent access, stress, and cancellation.
Transfer integration and soak tests exercise the shared operation path, rather
than duplicating platform-specific copy logic. The focused APFS image harness
(`Scripts/run_apfs_fault_tests.sh`) verifies that one inaccessible destination
reports failure while another can finish. `Scripts/run_soak_tests.sh` runs a
seeded, repeatable transfer soak test. Physical cable, power, hub, and exFAT
fault cases require the procedure in `docs/HARDWARE_TESTING.md`.
