# Architecture Task 4 Report: Targeted Concurrency Diagnostics

## Scope

- Enabled `SWIFT_STRICT_CONCURRENCY = targeted` for Debug and Release on the `BitMatch` and `BitMatch-iPad` application targets.
- Retained `SWIFT_VERSION = 5.0` in every affected configuration.

## Baseline

Captured before the project setting change, outside the repository:

- `DERIVED_DATA_ROOT=/tmp/bitmatch-task4-baseline-derived bash test.sh mac-build`
  - Log: `/tmp/bitmatch-task4-baseline-mac-debug.log`
  - Project Swift warnings: none.
- `DERIVED_DATA_ROOT=/tmp/bitmatch-task4-baseline-derived bash test.sh ipad-build`
  - Log: `/tmp/bitmatch-task4-baseline-ipad-debug.log`
  - Project Swift warnings: none.

Both baseline builds emitted only existing Xcode/tooling warnings (destination selection or App Intents metadata extraction), not Swift source diagnostics.

## Diagnostics Addressed

- `IOSBackgroundTaskService`: moved the UIKit reads in the timer callback into its `@MainActor` task.
- `SharedFileOperationsService`: Sendable pause callbacks capture the `PauseState` actor rather than the non-Sendable service instance.
- `AsyncUtils`: `BackgroundTask.execute` requires its main-actor completion closure to be `@Sendable`.

No `@unchecked Sendable` annotations were added.

## Verification

- `bash test.sh mac-test` — `** TEST SUCCEEDED **`
- `bash test.sh ipad-build` — `** BUILD SUCCEEDED **`
- `bash test.sh release-builds` — macOS and iPad `** BUILD SUCCEEDED **`

Final logs are stored outside the repository in `/tmp/bitmatch-task4-*.log`. The final audit found no warnings from production Swift files. `.derived-data` was removed after verification.
