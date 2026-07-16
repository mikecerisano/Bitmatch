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
