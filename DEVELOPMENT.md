# BitMatch Development Guide

## Development History & Context

### Major Milestones

#### 1. Initial Architecture (Pre-Shared)
- Separate macOS and iPad codebases
- Duplicated business logic
- Platform-specific implementations throughout

#### 2. Shared Architecture Migration
- Moved core business logic to `Shared/Core/`
- Created platform abstraction layer
- Unified data models across platforms

#### 3. Interface Consistency Project
- Enhanced iPad interface to match macOS sophistication  
- Implemented collapsible sections and professional layouts
- Achieved visual and functional parity between platforms

#### 4. Critical Bug Fixes
- Fixed iOS document picker continuation leaks
- Resolved compilation errors from automated changes
- Restored proper left-right layout in iPad interface

## Current Development Status

### ✅ Completed (Production Ready)
- **Shared Core Architecture**: Complete migration with all services shared
- **Platform Abstraction**: Clean separation of platform-specific code
- **iPad Interface Enhancement**: Professional UI matching macOS patterns
- **Folder Selection**: Fixed iOS security-scoped resource handling
- **Interface Consistency**: Both platforms feature-complete and visually consistent
- **Compilation**: All syntax and type errors resolved

### 🎯 Active Development Areas
- **UI Polish**: Minor visual refinements and animations
- **Testing**: Comprehensive testing of all operation flows
- **Performance**: Optimization for large file sets

### 💡 Future Enhancements
- **Additional Camera Support**: Expand camera detection database
- **Advanced Reporting**: Enhanced analytics and visualization
- **Cloud Integration**: Support for cloud storage destinations
- **Batch Operations**: Multiple transfer queue management

## Key Technical Decisions

### Architecture Patterns

#### 1. Protocol-Driven Platform Abstraction
```swift
protocol FileSystemService {
    func selectSourceFolder() async -> URL?
    // Platform implementations handle specifics
}

// iOS Implementation
class IOSFileSystemService: FileSystemService {
    func selectSourceFolder() async -> URL? {
        // UIDocumentPickerViewController implementation
    }
}

// macOS Implementation  
class MacOSFileSystemService: FileSystemService {
    func selectSourceFolder() async -> URL? {
        // NSOpenPanel implementation
    }
}
```

**Rationale**: Enables shared business logic while maintaining platform-specific optimizations.

#### 2. Reactive State Management
```swift
class SharedAppCoordinator: ObservableObject {
    @Published var operationState: OperationState = .idle
    @Published var progress: OperationProgress?
}
```

**Rationale**: SwiftUI's reactive system automatically updates UI when state changes, reducing complexity and bugs.

#### 3. Async/Await for File Operations
```swift
func startOperation() async {
    await withTaskGroup(of: Void.self) { group in
        for destination in destinations {
            group.addTask { await copyFiles(to: destination) }
        }
    }
}
```

**Rationale**: Modern Swift concurrency prevents UI blocking and enables clean cancellation handling.

### UI Design Decisions

#### 1. Collapsible Sections (iPad)
**Implementation**: Professional expandable sections for camera labeling and verification modes
**Rationale**: Maintains clean interface while providing full functionality on smaller screens

#### 2. Left‑Right Layout (Source | Destination)
**Implementation**: Side‑by‑side source and destination selection on both Mac and iPad (with touch‑optimized cards on iPad). The iPad view shows the selected folder name immediately; file counts/sizes appear after the folder analysis completes.
**Rationale**: Intuitive data flow visualization for professional video workflows

#### 3. Professional Card Design
**Implementation**: Sophisticated card layouts with proper spacing and visual hierarchy
**Rationale**: Matches industry-standard applications (Silverstack, ShotPut Pro)

## Critical Code Areas

### 1. iOS Document Picker (Delegate Retention + Scopes)
**File**: `Platforms/iOS/Services/IOSFileSystemService.swift`
**Issue (historical)**: Document picker delegate could be deallocated before completion.
**Solution**: The service retains the delegate (`currentDelegate`) and clears it on completion. All file access uses security‑scoped URLs with `defer` cleanup.

```swift
class IOSFileSystemService: NSObject, FileSystemService {
    private var currentDelegate: DocumentPickerDelegate?
    @MainActor private func selectFolder(allowMultiple: Bool) async -> [URL] {
        await withCheckedContinuation { continuation in
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            let delegate = DocumentPickerDelegate { [weak self] urls in
                self?.currentDelegate = nil
                continuation.resume(returning: urls)
            }
            self.currentDelegate = delegate
            picker.delegate = delegate
            // present picker ...
        }
    }
}
```

### 2. Security-Scoped Resource Management (iOS)
**Pattern**: Always use proper resource lifecycle management
```swift
func processFiles(in folderURL: URL) async throws {
    guard folderURL.startAccessingSecurityScopedResource() else {
        throw BitMatchError.fileAccessDenied(folderURL)
    }
    defer { folderURL.stopAccessingSecurityScopedResource() }
    
    // Process files...
}
```

### 3. State Update Threading
**Pattern**: Ensure UI updates happen on main thread
```swift
@MainActor
func updateProgress(_ progress: OperationProgress) {
    self.progress = progress  // Safe on main thread
}
```

## Development Workflow

### 1. Making Changes to Shared Code
- Test on both macOS and iPad targets
- Ensure protocol contracts are maintained
- Update both platform managers if needed

### 2. Platform-Specific Changes
- Keep changes isolated to platform directories
- Update corresponding platform if symmetry is needed
- Test edge cases specific to that platform

### 3. UI Changes
- Maintain design consistency between platforms
- Consider touch vs. mouse interaction patterns
- Test across different screen sizes

### 4. Adding New Features
1. Define shared data models in appropriate model file
2. Add business logic to shared services
3. Update platform managers if system integration needed
4. Implement UI in both platforms (unless platform-specific)
5. Add error handling and edge cases
6. Test full operation flow

## Debugging Guide

### Common Issues

#### 1. Folder Selection Not Working (iOS)
**Symptoms**: Document picker appears but selection doesn't register
**Likely Cause**: Delegate lifecycle issues or continuation problems
**Debug**: Check for "SWIFT TASK CONTINUATION MISUSE" in console; verify `currentDelegate` retention and that the picker is presented from a valid root view controller.

#### 2. UI Not Updating After State Change
**Symptoms**: State changes but UI doesn't reflect updates
**Likely Cause**: Threading issues or missing @Published
**Debug**: Verify main thread execution and ObservableObject conformance

#### 3. File Access Denied (iOS)
**Symptoms**: Cannot read selected folders or files
**Likely Cause**: Security-scoped resource not acquired or expired
**Debug**: Check startAccessingSecurityScopedResource() calls
  - Ensure `with defer { stopAccessing... }` is used for all scans/copies/size checks. See `IOSFileSystemService` for the pattern.

### Swift 6 Concurrency Notes
- Avoid iterating `NSDirectoryEnumerator` using `for in` inside async contexts; use `while let url = enumerator.nextObject() as? URL` inside a background task.
- Prefer CryptoKit over CommonCrypto where possible. MD5 is implemented via `Insecure.MD5` for legacy compatibility; SHA‑256 remains the default.
- Watch actor isolation: UI‑facing methods on managers are `@MainActor`; non‑isolated service properties are exposed via computed accessors.

### Debug Logging Strategy
Use structured console logging for different subsystems:
```swift
// File operations
print("📁 File operation: \(operation)")

// UI state changes  
print("🖥️ UI state: \(state)")

// Platform integration
print("📱 Platform call: \(method)")

// Errors
print("❌ Error: \(error)")
```

## Testing Guidelines

### Unit Tests
- Test shared business logic in isolation
- Mock platform managers for consistent testing
- Cover error conditions and edge cases

### Integration Tests  
- Test full operation flows end-to-end
- Verify platform-specific behavior
- Test error recovery and user cancellation

### Manual Testing Checklist
- [ ] Folder selection works on both platforms
- [ ] File operations complete successfully
- [ ] Progress updates display correctly
- [ ] Error conditions show appropriate messages
- [ ] UI remains responsive during operations
- [ ] Memory usage stays reasonable for large operations

## Testing & Coverage

- Run tests with coverage:
  - `xcodebuild test -scheme BitMatch -enableCodeCoverage YES -resultBundlePath coverage.xcresult`
- Coverage summary:
  - `xcrun xccov view --report coverage.xcresult`
- JSON coverage for tooling/CI:
  - `xcrun xccov view --report --json coverage.xcresult`
- Convenience: `bash test.sh`

## Swift 6 Concurrency Notes (Updates)

- Do not call actor‑isolated methods from nonisolated initializers; perform synchronous file reads directly in init when needed.
- Heavy filesystem enumeration must not run on the main actor; use `Task.detached` and marshal results back to main.

## Logging

- Use `SharedLogger` for all logging; `AppLogger` forwards to `SharedLogger` to preserve existing call sites.

## TODO Policy

- Avoid leaving naked TODOs in committed code; prefer “Future enhancement:” comments with clear intent or file an issue.

## Deferred Features

- Cancel-time cleanup of copied files is intentionally disabled until the transfer pipeline has extended field validation.

## Project Structure & Schemes

- Open `BitMatch.xcodeproj` in Xcode 15+
- Schemes:
  - `BitMatch` (macOS app)
  - `BitMatch-iPad` (iOS/iPadOS app)
- Shared code lives under `Shared/Core/{Models,Services}` and is compiled into both schemes.

## Code Review Checklist

- Shared vs platform boundaries respected (no UIKit/AppKit in shared files)
- `@Published` used for coordinator state that drives UI
- Main‑actor correctness for UI‑touching methods
- iOS: security‑scoped URLs acquired/released appropriately
- Progress callbacks update coordinator on main actor
- Avoid deeply nested SwiftUI modifiers; prefer extracted subviews for complex rows

## Code Style Guidelines

### Swift Conventions
- Use async/await for asynchronous operations
- Prefer `@Published` properties for reactive state
- Use meaningful variable and function names
- Add comments for complex business logic

### SwiftUI Patterns
- Break large views into smaller components
- Use `@ObservedObject` for coordinator pattern
- Prefer computed properties for derived state
- Use proper view modifiers for styling

### Error Handling
- Use `BitMatchError` enum for user-facing errors
- Provide descriptive error messages
- Handle platform-specific errors appropriately
- Always clean up resources in error cases

## Deployment Notes

### Build Configuration
- Ensure both targets build successfully
- Verify code signing and provisioning
- Test on actual devices, not just simulator

### Performance Considerations
- Test with large file sets (1000+ files)
- Monitor memory usage during operations
- Verify UI responsiveness under load

### Platform-Specific Requirements
- **iOS**: Requires document picker permissions
- **macOS**: May require file system access permissions
- Both: Ensure proper error handling for permission denials
