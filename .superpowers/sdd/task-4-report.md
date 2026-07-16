# Phase 2 Task 4 Report: Trusted Local Artifact Bridge

## Implemented

- Added `RemoteBackupCoordinator`, which permits queueing only cards already
  marked `.locallySafe` with completed local evidence and a confirmed
  fingerprint. Copying and failed cards throw
  `RemoteBackupError.localArtifactNotVerified`.
- Builds immutable manifests only from verified `ResultRow.destinationPath`
  values. It derives entry paths below the rendered package, requires matching
  SHA-256 evidence across verified local destinations, and never derives an
  artifact root from the source-card path.
- Stores each package's security-scoped bookmark in Keychain behind an opaque
  `remote-artifact.<manifest UUID>` reference; the bookmark bytes do not enter
  Core Data payloads.
- Connects the coordinator to the persistent queue's injected artifact
  resolver. Before provider creation, queue runs resolve the bookmark and
  revalidate package containment, regular-file size, and SHA-256 equality.
- Added select, queue, pause, and retry commands through the photographer view
  model and app coordinator. Remote failures write only remote feedback and
  never call `operationFailed()` or alter local evidence.

## Tests added

- `RemoteBackupCoordinatorTests` covers copying/failed-card rejection,
  destination-package (not source-card) bookmarking, and checksum drift at
  resolver time.
- `PhotographerJobViewModelTests` covers that remote queue failure leaves a
  copying card's local evidence untouched.

## Validation

- `git diff --check` passed.
- `bash test.sh mac-build` passed with exit status 0 (compile-only).
- A compile-only `xcodebuild build-for-testing` compiled both new test files;
  the full target then failed on pre-existing
  `BitMatchTests/PhotographerReportTests.swift` Swift Testing macro handling
  of a throwing `allSatisfy` closure. No test binary, simulator, or app was
  launched.

## Scope notes

- No SFTP provider, network upload, or Citadel dependency was added. The
  provider factory remains deliberately unavailable until Task 5.

## Review follow-up

- Replaced raw local-artifact URLs with an ownership-safe lease. Resolving a
  bookmark starts scoped access before local revalidation, and the queue
  releases it exactly once after provider upload/verification or every error
  and cancellation path; providers never receive an unleased URL.
- Hardened resolver coverage for stale/checksum failures and symlink escape
  containment. The resolved regular file must remain below the resolved
  package root.
- Queue creation now records every successfully saved item and rolls each one
  back before removing its manifest and bookmark if a later persistence write
  fails, preventing orphaned restore records.
- Added focused test coverage for lease lifecycle, validation cleanup,
  symlink escape rejection, and second-item partial-save rollback. Per task
  constraints these tests were compile-checked only; no test binary, app, or
  simulator was launched.
