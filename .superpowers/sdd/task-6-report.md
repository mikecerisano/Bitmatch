# Phase 2 Task 6 Report: Off-site Backup Evidence UI and Reports

## Implemented

- Added a compact optional **Off-site Backup** stage to photographer setup. It
  expands only after enablement and selects from persisted SFTP destination
  profiles; it displays profile metadata, verification mode, host-key
  confirmation requirement, and read-back data-cost warning without exposing
  credentials, agent state, private-key paths, or passphrases.
- Added remote evidence to each dashboard card while retaining the independent
  local verdict. `Locally Safe`, `Uploaded · Unverified`, and `Fully Backed Up`
  remain distinct; only valid SHA-256/read-back evidence yields fully backed up.
- Added evidence-only report payload fields and PDF/CSV presentation for remote
  status, path, verification evidence, warning/error summary, and timestamps.
  `fullyBackedUpAt` is nil for unverified uploads, so remote progress cannot
  rewrite local-safety evidence.
- Guarded the macOS-only remote queue, provider boundary, and artifact
  coordinator from the iPad target. Shared remote models remain available for
  persisted/evidence presentation; iPad does not compile or expose uploads.

## Tests added

- Presentation coverage for the disabled compact stage and warning-colored
  unverified uploads.
- Report coverage that an unverified remote upload preserves local safety,
  has no fully-backed-up timestamp, and JSON payload generation contains no
  private-key string.

## Validation

- `git diff --check` passed.
- `bash test.sh mac-build` passed with exit status 0 (compile-only).
- `bash test.sh ipad-build` passed with exit status 0 (compile-only).
- No app, simulator, test binary, or test execution was launched.

## Read-only safety review

- The UI and reports consume profile metadata and derived remote evidence only;
  credential material, private keys, passphrases, bookmark bytes, and agent
  sockets do not cross this boundary.
- Unknown/changed host keys are described as requiring confirmation before
  SSH-agent authentication; Task 5 retains the fail-closed transport behavior.
- No changes weaken remote path validation, artifact revalidation, resumable
  upload handling, or no-replace promotion. Local copy safety remains
  authoritative and independent of remote state.

## Follow-up integration correction

- A locally safe card now offers a queue action when off-site backup is
  configured; the coordinator restores the durable items and calls `run` for
  each one rather than merely restoring them.
- First unknown-host trust now pauses at a coordinator-owned SwiftUI alert that
  displays the host, port, and OpenSSH SHA-256 fingerprint. Acceptance is the
  only path that resumes provider preflight; dismissal/cancel returns false and
  remains fail-closed before SSH-agent authentication.
- Enabling the optional stage without saved profiles keeps it expanded so the
  no-profile guidance remains reachable. The SFTP summary uses actual Swift
  interpolation for profile metadata.

## Final integration correction

- The OpenSSH trust request/confirmation type is platform-neutral while the
  implementation remains macOS-only, so the iPad target can type-check the
  unavailable factory path.
- After each queue worker run, the app reads its durable queue item state and
  refreshes the photographer card summary. Dashboard and report evidence now
  advances beyond the initially queued state without changing local safety.
- Concurrent host-trust requests reject the later continuation with `false`;
  no prompt or continuation is overwritten.
