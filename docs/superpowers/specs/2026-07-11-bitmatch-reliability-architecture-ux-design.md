# BitMatch Reliability, Architecture, and Setup UX Design

Date: 2026-07-11
Status: Approved design, pending implementation plan

## Purpose

Improve BitMatch without replacing its proven transfer core. The work will strengthen automated verification, finish the shared-core migration, clarify concurrency boundaries, and simplify transfer setup. Both app targets must remain buildable and testable after every stage.

## Goals

- Make transfer failure scenarios reproducible on disposable storage.
- Build both platforms and run the supported tests in continuous integration.
- Keep one canonical operation path in the shared core.
- Remove code proved unreachable from both app targets.
- Replace delayed change forwarding with explicit state bindings.
- Adopt stricter Swift concurrency diagnostics without a broad rewrite.
- Present setup as a clear transfer plan with a prominent safety verdict.
- Preserve transfer behavior, saved preferences, report formats, and in-progress UI.

## Non-goals

- Rewriting the copy, verification, report, or safety services.
- Replacing SwiftUI or introducing a third-party architecture framework.
- Claiming that software simulation reproduces a physical cable pull.
- Changing report file formats or invalidating saved preferences.
- Rewriting the README before implementation stabilizes. Documentation and screenshots will be corrected at the end.

## Delivery Strategy

The work will use staged consolidation. Each stage must build both schemes, pass all applicable tests, and leave the repository free of generated artifacts.

1. Add CI, explicit test commands, and disposable fault-test infrastructure.
2. Remove confirmed dead code, simplify the macOS adapter, and tighten concurrency boundaries.
3. Implement the transfer-plan setup UI on macOS, then apply the same hierarchy to iPadOS.
4. Update documentation and screenshots to match the finished behavior.

## Canonical Architecture

`SharedAppCoordinator`, `CopyVerifyExecutor`, `ComparisonCoordinator`, `ReportCoordinator`, and the shared file-operation services remain the canonical operation path. `SafetyValidator` and the shared operation services remain authoritative even when the UI performs an earlier readiness check.

The macOS `AppCoordinator` remains a compatibility adapter during this project. It may expose macOS-specific view models, but it must not maintain a competing operation state machine. Explicit Combine pipelines will replace delayed `objectWillChange` forwarding. State must flow in one direction:

1. Selection and option controls update their existing models.
2. A start action creates the shared operation input.
3. The shared coordinator owns the operation lifecycle.
4. Explicit bindings project shared progress and results into macOS presentation state.

Before deleting a legacy type, repository-wide reference checks and target builds must prove that neither app uses it. The initial candidates are the orphaned `OperationViewModel` operation stack, the unused `AppConfiguration`, and the unused `DependencyContainer` experiment. The implementation plan will list the exact files after dependency tracing.

## Concurrency Boundaries

The project will adopt stricter concurrency checking incrementally. This work will:

- mark platform UI entry points with explicit actor isolation;
- remove synchronous main-queue hops where an actor-isolated or asynchronous contract can replace them;
- preserve cancellation and pause behavior across actor boundaries;
- avoid detached tasks unless the work must escape inherited actor context;
- fix new warnings in touched code before increasing the target-wide diagnostic level.

The first pass will enable diagnostics that report problems without forcing an immediate Swift language-mode migration. Later stages may raise enforcement only when both targets build cleanly.

## CI and Test Commands

`test.sh` will expose explicit commands for supported build and test jobs. Command names and destinations must make the selected platform and test bundle clear. At minimum, local automation will support:

- macOS Debug build;
- macOS unit tests;
- iPadOS simulator Debug build;
- iPadOS tests when a compatible simulator runtime is available;
- Release builds for both schemes.

GitHub Actions will run on pushes and pull requests. It will build both schemes and run the macOS unit suite. iPadOS simulator tests will run only on a runner that provides the required runtime; the iPadOS build remains mandatory.

CI must use isolated derived-data paths when jobs run concurrently. This prevents the Xcode build-database lock observed when two builds shared one directory.

## Disposable Fault Testing

Automated fault tests must operate only on temporary directories or newly created disposable disk images. Every script must validate its root before deleting, filling, unmounting, or corrupting data.

The deterministic suite will cover:

- insufficient destination space;
- source files that change or shrink during copying;
- cancellation followed by cleanup or resume;
- existing matching and conflicting destination files;
- unsafe nested, duplicate, symlinked, case-colliding, and Unicode-colliding paths;
- one failed destination in a multi-destination operation;
- checksum mismatch and report classification after a failed verification.

Where APFS disk images provide useful control, the harness will create, size, mount, and dispose of them itself. Tests that can use ordinary temporary directories will remain unit or integration tests for speed.

## Soak and Hardware Tests

A local soak runner will generate representative camera-card trees containing large media files, sidecars, hidden files, empty directories, and nested folders. It will repeat transfers, independently recompute hashes, and emit a machine-readable summary. A seed will make failures reproducible.

Physical disconnect testing remains a manual hardware procedure because CI cannot faithfully reproduce cable, hub, controller, and power failures. The repository will provide a concise checklist and a safe disposable-data setup for:

- source removal during copy and verification;
- one destination disappearing while another remains mounted;
- sleep, backgrounding, cancellation, and relaunch;
- low-power or slow-device behavior;
- repeated operations across different file systems.

## Transfer-Plan Presentation Model

A small presentation model will summarize existing state for the setup UI. It may expose:

- source name, analysis state, file count, and byte count;
- destination names, free-space state, and aggregate readiness;
- selected verification mode;
- camera-label summary;
- report summary;
- blocking issues and non-blocking warnings;
- primary-action title and enabled state.

This model contains no copy, verification, path-resolution, or safety policy. It derives explanations from existing validators and view models. The shared core repeats all safety checks when an operation starts.

## Setup-Screen UX

The idle setup screen will retain BitMatch's dark palette, typography, navigation, and window footprint. It will replace the expanded configuration layout with a transfer-plan summary.

The main hierarchy will be:

1. Source card: selection action, folder name, analysis progress, file count, and size.
2. Backup card: destination selections and capacity status.
3. Preflight card: passed, analyzing, warning, or blocked state with specific reasons.
4. Compact option summary: verification, naming, and report settings.
5. Primary action: `Start verified copy` when checksum verification is active.

Camera labeling, verification choices, and report settings will live in one Options surface. Quick mode and other material risks remain visible outside that surface. A disabled action must have an adjacent explanation.

The UI will preserve drag and drop, keyboard shortcuts, recent destinations, mode navigation, and the compact in-progress interface. Touched controls will gain meaningful accessibility labels, predictable focus order, sufficient contrast, and reduced-motion behavior.

iPadOS will use the same information hierarchy, adapted to its responsive layout. It will not copy the macOS arrangement pixel for pixel.

## Error Handling

The setup UI will distinguish these states:

- incomplete selection;
- folder analysis in progress;
- preflight passed;
- non-blocking warning;
- blocking validation failure;
- operation-start failure after the final core validation.

Messages must identify the affected source or destination and suggest a specific correction. The UI must never convert a core validation failure into success or suppress it because an earlier readiness check passed.

Fault-test scripts must stop on unsafe roots, failed setup, or cleanup errors. They must retain diagnostic logs after a failed run.

## Compatibility

The implementation must preserve:

- persisted verification and report preferences;
- destination-label settings;
- source and destination selection behavior;
- report schemas and output names unless an existing bug requires correction;
- resume and cancellation semantics;
- current verification defaults;
- macOS and iPadOS deployment targets.

## Verification Gates

Every stage must satisfy these gates before the next begins:

- clean macOS Debug build;
- clean iPadOS simulator Debug build;
- all existing macOS unit tests pass;
- new tests for the stage pass;
- Release builds pass before final completion;
- no unexpected warnings introduced in touched files;
- `git status` contains no generated build, test, disk-image, or soak artifacts.

The UI stage also requires visual checks at supported window sizes, keyboard navigation, reduced motion, and representative empty, analyzing, ready, warning, blocked, active, and completed states.

## Completion Criteria

The project is complete when:

- contributors can reproduce supported builds and tests through documented commands;
- CI builds both app targets and runs the supported automated tests;
- disposable fault and soak tools produce reproducible results without touching arbitrary drives;
- the app uses one shared operation path without the confirmed legacy stack;
- touched concurrency boundaries build cleanly under the chosen diagnostics;
- macOS and iPadOS present a concise transfer plan before starting;
- current settings, reports, transfer behavior, and safety checks remain compatible;
- final documentation and screenshots describe the resulting product accurately.
