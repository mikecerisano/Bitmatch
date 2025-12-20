# BitMatch - Professional Video File Transfer & Verification

BitMatch is a professional video production tool for copying and verifying file integrity across multiple backup destinations. It supports both macOS and iPad platforms with sophisticated interfaces designed for professional video workflows.

## Overview

BitMatch provides industry-standard file transfer capabilities with integrity verification, supporting workflows similar to Silverstack and ShotPut Pro. The application features automatic camera detection, multiple verification modes, and comprehensive reporting.

What’s new (current build)
- Shared core drives both macOS and iPad (single code path for operations)
- Persistent checksum cache (cross‑platform, 1h TTL) speeds re‑verification dramatically
- Off‑main folder analysis with parallel batching for smooth UI on large folders
- Unified logging via SharedLogger

## Build & Run

Prereqs
- Xcode 15 or newer
- macOS 14+ for building both targets

Schemes
- macOS app: select the `BitMatch` scheme and run
- iPad app: select the `BitMatch-iPad` scheme, choose an iPad simulator or device, and run

iOS signing
- The iPad target requires a valid team. In Xcode, open `Targets → BitMatch-iPad → Signing & Capabilities` and set your team.

Notes
- The iPad app uses security‑scoped URLs. All file access must originate from the document picker; direct file system paths won’t work outside app‑granted scopes.
- If you change shared models/services, build both schemes to catch platform issues early.
- macOS uses SharedAppCoordinator by default; the legacy flow remains but is no longer used.

## Platform Support

- **macOS**: Full-featured desktop application
- **iPad**: Touch-optimized interface with same functionality

## Key Features

### Core Functionality
- **Copy & Verify**: Copy files to multiple backup destinations with integrity verification
- **Compare Folders**: Compare two folders to identify differences
- **Master Report**: Generate comprehensive transfer reports from completed operations

### Professional Features
- **Camera Detection**: Automatic detection of camera cards (Sony, Canon, ARRI, RED, etc.)
- **Multiple Verification Modes**: Quick, Standard, Thorough, Paranoid with MHL support
- **Folder Labeling**: Automatic camera-based folder naming with customizable patterns
- **Progress Tracking**: Real-time progress with speed, ETA, and detailed statistics
- **Report Generation**: Professional PDF and CSV reports

## Architecture

### Shared Core Architecture
```
Shared/
├── Core/
│   ├── Models/           # Shared data models
│   │   ├── SharedModels.swift
│   │   ├── CameraModels.swift
│   │   ├── OperationModels.swift
│   │   └── TransferModels.swift
│   └── Services/         # Shared business logic
│       ├── SharedAppCoordinator.swift
│       ├── ServiceProtocols.swift
│       ├── SharedChecksumService.swift
│       ├── SharedFileOperationsService.swift
│       ├── SharedCameraDetectionService.swift
│       ├── SharedReportGenerationService.swift
│       ├── OperationStateService.swift
│       ├── OperationTimingService.swift
│       ├── ErrorReportingService.swift
│       └── File/         # Shared file operation helpers
│           ├── FileCopyService.swift
│           ├── PreScanService.swift
│           └── FileTreeEnumerator.swift
```

### Platform-Specific Implementation
```
BitMatch/                 # macOS Application
├── App/
│   ├── ContentView.swift
│   └── AppCoordinator.swift
├── Views/               # macOS UI Components
├── Core/               # macOS-specific services
└── UI/                 # macOS UI utilities

BitMatch-iPad/          # iPad Application
├── ContentView.swift
├── Views/              # iPad UI Components
│   ├── ModularContentView.swift
│   ├── CopyAndVerifyView.swift
│   ├── HeaderTabsView.swift
│   ├── OperationProgressView.swift
│   └── CompletionSummaryView.swift
└── App/               # iPad app configuration

Platforms/             # Platform-specific services
├── iOS/
│   └── Services/
│       ├── IOSPlatformManager.swift
│       ├── IOSFileSystemService.swift
│       └── IOSDriverScanner.swift
└── macOS/
    └── Services/
        ├── MacOSPlatformManager.swift
        └── MacOSFileSystemService.swift
```

## Current Status

### ✅ Completed Features
- **Shared Architecture**: Complete migration to shared core services
- **iPad Interface**: Fully functional touch-optimized interface
- **Folder Selection**: Fixed iOS document picker implementation
- **Interface Consistency**: Both platforms match in functionality and design
- **Professional UI**: Collapsible sections, professional cards, sophisticated layouts
- **Master Report**: Volume scanning and comprehensive report generation
- **Timing & Error Services**: Integrated `OperationTimingService`, `OperationStateService`, and `ErrorReportingService` across flows

### 🎯 Production Ready
The application is currently in a production-ready state with:
- All critical compilation errors resolved
- Interface consistency between platforms achieved
- Core functionality working on both macOS and iPad
- Professional-grade UI matching video industry standards

## Troubleshooting

- iPad: folder selection doesn’t show the chosen path
  - Ensure you picked a folder via the document picker. BitMatch displays the selection immediately; file counts and sizes appear after a short analysis pass.
- iPad: cannot access external volumes
  - iOS requires picking an external location via the document picker to grant access. Re‑select the volume or subfolder.
- UI not updating after state change
  - Verify the affected property is `@Published` on `SharedAppCoordinator` and updated on the main actor.
- Slow build/type‑check on iPad views
  - Prefer extracted row/section subviews and avoid deeply nested modifiers; we’ve applied this pattern to verification lists.

Swift 6 notes
- Avoid iterating NSDirectoryEnumerator directly in async contexts (e.g., `for in enumerator`). Use `while let url = enumerator.nextObject() as? URL` inside a background task to stay Swift‑6‑safe.
- Prefer CryptoKit for hashing; MD5 remains available as a legacy option via `Insecure.MD5` and is not recommended for security contexts. SHA‑256 is the default.

## Documentation

- Architecture: ARCHITECTURE.md
- Features: FEATURES.md
- Development guide: DEVELOPMENT.md
- Migration notes: [MIGRATION_SUMMARY.md](MIGRATION_SUMMARY.md)
 - Changelog: [CHANGELOG.md](CHANGELOG.md)

## Running Tests with Coverage

- Enable coverage and run tests:
  - `xcodebuild test -scheme BitMatch -enableCodeCoverage YES -resultBundlePath coverage.xcresult`
- View a summary report (requires Xcode command line tools):
  - `xcrun xccov view --report coverage.xcresult`
- View JSON report (for CI or tooling):
  - `xcrun xccov view --report --json coverage.xcresult`
 - Convenience: run `bash test.sh` from the repo root to execute tests with coverage and print reports.

## Performance Notes

- Checksum cache persists within `~/Library/Caches` and auto‑invalidates on file size or modification time changes.
- Folder info enumeration runs off the main thread and uses small batches (default 6 concurrent) to avoid saturating disks.
- On iOS, file listing uses a single folder security scope with per‑file fallbacks only on errors.

## Technical Details

### Key Technologies
- **SwiftUI**: Modern declarative UI framework
- **Swift Concurrency**: Async/await for file operations
- **Security-Scoped URLs**: iOS file system access
- **MHL Standard**: Media Hash List compliance for professional video
- **Core Graphics**: Professional PDF report generation

### Verification Modes
1. **Quick**: File size comparison only
2. **Standard**: Basic SHA-256 checksum verification
3. **Thorough**: Multiple checksum algorithms (SHA-256, MD5)
4. **Paranoid**: Byte-by-byte comparison + multiple checksums + MHL

### Camera Support
- Sony (FX6, FX3, A7S series)
- Canon (C70, EOS series)
- ARRI (Alexa, Amira)
- RED (Dragon series)
- Blackmagic Design
- Panasonic, Fujifilm, Nikon
- GoPro, DJI, Insta360
- Generic DCIM structures

## Development Notes

### Recent Major Changes
1. **Architecture Migration**: Moved from separate macOS/iPad codebases to shared architecture
2. **Interface Enhancement**: Enhanced iPad interface to match macOS sophistication
3. **Bug Fixes**: Resolved iOS document picker continuation leaks
4. **Layout Improvements**: Restored proper left-right source/destination layout

### Code Quality
- Clean, well-documented Swift code
- MVVM architecture with ObservableObject patterns
- Protocol-driven design for platform abstraction
- Comprehensive error handling and user feedback
