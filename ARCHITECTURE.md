# BitMatch Architecture Documentation

## Overview

BitMatch uses a shared core architecture that enables code reuse between macOS and iPad platforms while maintaining platform-specific optimizations.

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

### File System Services

#### FileSystemService Protocol
```swift
protocol FileSystemService {
    func selectSourceFolder() async -> URL?
    func selectDestinationFolders() async -> [URL]
    func validateFileAccess(url: URL) async -> Bool
    func getFileList(from folderURL: URL) async throws -> [URL]
    func copyFile(from sourceURL: URL, to destinationURL: URL) async throws
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

Key Components:
- `CopyAndVerifyView`: Enhanced touch interface with collapsible sections
- `CompareFoldersView`: Side-by-side folder selection
- `MasterReportView`: Volume scanning and report generation
- `OperationProgressView`: Real-time progress display
- `CompletionSummaryView`: Operation completion interface

## Flow Diagrams

### Copy & Verify (high level)

1. UI sets `sourceURL` and `destinationURLs` on `SharedAppCoordinator`
2. User taps Start → `startOperation()`
3. Coordinator starts services:
   - `OperationTimingService.startOperation(...)`
   - `OperationStateService.startOperation(...)`
   - `ErrorReportingService.startErrorTracking(...)`
4. `SharedFileOperationsService.performFileOperation(...)` kicks off, providing progress callbacks
5. Progress updates → coordinator updates `progress` + timing service → UI reacts
6. On completion: state services finalize; results mapped to `ResultRow` list
7. If reports enabled, `SharedReportGenerationService` is invoked

### Compare Folders (basic)

1. UI sets `leftURL` and `rightURL`
2. Coordinator `compareFolders()` enumerates both via `FileSystemService.getFileList` (skips hidden)
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
- Large file lists processed incrementally
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

### Integration Testing
- Full operation flows
- Platform-specific implementations
- Error condition handling

### UI Testing
- User interaction flows
- State management verification
- Platform-specific behavior validation
