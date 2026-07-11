# BitMatch Architecture and Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the confirmed legacy operation path, make adapter bindings explicit, and introduce concurrency diagnostics without changing transfer behavior.

**Architecture:** Shared coordinators and shared services remain authoritative. The macOS coordinator projects shared state into existing presentation objects through explicit Combine pipelines. Unused platform background-task protocol methods disappear; `IOSBackgroundTaskService` remains the sole iOS background-task owner.

**Tech Stack:** Swift 5 language mode, Combine, Swift concurrency diagnostics, Xcode project settings.

## Global Constraints

- Preserve settings keys, report formats, verification defaults, cancellation, pause, and resume behavior.
- Delete a type only after repository-wide reference tracing proves it unreachable.
- Build macOS and iPadOS after each deletion group.
- Add no third-party framework and do not migrate to Swift 6 language mode in this plan.

---

### Task 1: Prove and remove the orphaned operation stack

**Files:**
- Delete after reference proof: `BitMatch/Core/ViewModels/OperationViewModel.swift`
- Delete after reference proof: `BitMatch/Core/Services/ComparisonOperationService.swift`
- Delete after reference proof: `BitMatch/Core/Services/File/VerifyService.swift`
- Delete after reference proof: `BitMatch/Core/Services/File/FileDiffService.swift`
- Delete after reference proof: `BitMatch/Core/Services/File/UnifiedFileOperationService.swift`
- Delete after reference proof: `BitMatch/Core/Services/File/FileCounter.swift`
- Delete after reference proof: `BitMatch/Core/Services/File/TempFileManager.swift`
- Delete after reference proof: `BitMatch/Core/Services/Configuration/AppConfiguration.swift`
- Delete after reference proof: `Shared/Core/Services/DependencyContainer.swift`
- Modify: `BitMatch/Core/ViewModels/SettingsViewModel.swift`

- [ ] **Step 1: Record the dependency proof**

Run one `rg -n` query for every candidate name across `*.swift`. Expected: references occur only inside the candidate group, except the stale `OperationViewModel` comment in `SettingsViewModel.swift`.

- [ ] **Step 2: Remove the stale comment and candidate files with apply_patch**

Do not delete `SharedAppCoordinator`, `CopyVerifyExecutor`, `ComparisonCoordinator`, `ReportCoordinator`, `SharedFileOperationsService`, `FileCopyService`, or `SafetyValidator`.

- [ ] **Step 3: Verify both targets and all unit tests**

Run: `bash test.sh mac-test && bash test.sh ipad-build`
Expected: all tests pass and both targets compile.

- [ ] **Step 4: Commit**

```bash
git add -A BitMatch/Core Shared/Core BitMatchTests
git commit -m "refactor: remove orphaned operation architecture"
```

### Task 2: Replace delayed coordinator forwarding

**Files:**
- Modify: `BitMatch/App/AppCoordinator.swift`
- Create: `BitMatchTests/AppCoordinatorBindingTests.swift`

**Interfaces:**
- Produces: `setupFileSelectionBindings()`, `setupProgressBindings()`, and `setupSharedCoordinatorBindings()` private methods.

- [ ] **Step 1: Write an observation test**

On `@MainActor`, subscribe to `AppCoordinator.objectWillChange`, update `fileSelectionViewModel.sourceURL`, and assert a notification arrives on the next run-loop turn without sleeping for a fixed duration. Repeat for `sharedCoordinator.operationState` through a test-only transition already exposed by the coordinator.

- [ ] **Step 2: Confirm the current implementation depends on fixed sleeps**

Run: `rg -n 'Task\.sleep\(nanoseconds: 1_000_000\)' BitMatch/App/AppCoordinator.swift`
Expected: two matches.

- [ ] **Step 3: Introduce explicit pipelines**

Split `setupObservers()` by responsibility. Replace child `objectWillChange` forwarding with merged publishers for values used by `AppCoordinator` computed properties. Schedule delivery on `RunLoop.main` and call `objectWillChange.send()` without `Task.sleep`. Keep the existing throttled progress mapping and operation-state timer management.

- [ ] **Step 4: Verify bindings and full behavior**

Run: `bash test.sh mac-test && bash test.sh ipad-build`
Expected: all tests pass; `rg` finds no fixed one-millisecond forwarding sleep.

- [ ] **Step 5: Commit**

```bash
git add BitMatch/App/AppCoordinator.swift BitMatchTests/AppCoordinatorBindingTests.swift
git commit -m "refactor: make coordinator state bindings explicit"
```

### Task 3: Remove duplicate platform background-task APIs

**Files:**
- Modify: `Shared/Core/Services/ServiceProtocols.swift`
- Modify: `Platforms/iOS/Services/IOSPlatformManager.swift`
- Modify: `Platforms/macOS/Services/MacOSPlatformManager.swift`
- Modify: `BitMatchTests/SharedCompareFlowTests.swift`

**Interfaces:**
- Preserves: `IOSBackgroundTaskService.beginOperation(estimatedFiles:)` and `endOperation()` as the only background-task interface.

- [ ] **Step 1: Prove the protocol methods have no callers**

Run: `rg -n '\.(beginBackgroundTask|endBackgroundTask)\(' --glob '*.swift'`
Expected: only implementations and UIKit calls; no call through `PlatformManager`.

- [ ] **Step 2: Remove the unused requirements and implementations**

Delete `PlatformManager.beginBackgroundTask` and `endBackgroundTask`, both platform implementations, and the mock methods in `SharedCompareFlowTests`. This also removes `DispatchQueue.main.sync` from `IOSPlatformManager`.

- [ ] **Step 3: Verify actor-owned background behavior still builds**

Run: `bash test.sh mac-test && bash test.sh ipad-build`
Expected: all tests and builds pass; `rg -n 'DispatchQueue\.main\.sync' Platforms/iOS` returns no matches.

- [ ] **Step 4: Commit**

```bash
git add Shared/Core/Services/ServiceProtocols.swift Platforms BitMatchTests/SharedCompareFlowTests.swift
git commit -m "refactor: centralize iOS background task ownership"
```

### Task 4: Add targeted concurrency diagnostics

**Files:**
- Modify: `BitMatch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Capture warnings before the setting change**

Run both Debug builds with output saved outside the repository. Record warnings from project Swift files.

- [ ] **Step 2: Set targeted checking for both app targets**

Add `SWIFT_STRICT_CONCURRENCY = targeted;` to Debug and Release configurations for `BitMatch` and `BitMatch-iPad`. Keep `SWIFT_VERSION = 5.0`.

- [ ] **Step 3: Fix diagnostics only in touched boundaries**

Use `@MainActor`, `nonisolated`, or immutable `Sendable` data where the compiler identifies a real boundary. Do not add `@unchecked Sendable` to production code merely to silence a warning.

- [ ] **Step 4: Verify Debug, Release, and tests**

Run: `bash test.sh mac-test && bash test.sh ipad-build && bash test.sh release-builds`
Expected: all commands exit 0 with no new warnings in touched files.

- [ ] **Step 5: Commit**

```bash
git add BitMatch.xcodeproj Shared Platforms BitMatch
git commit -m "build: enable targeted concurrency diagnostics"
```
