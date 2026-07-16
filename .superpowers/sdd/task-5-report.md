# Phase 2 Task 5 Report: Secure SFTP Provider Boundary

## Implemented

- Added Citadel 0.12.1 as a Swift Package dependency of the macOS `BitMatch`
  target only. The iPad target has no product dependency; the shared factory
  returns `RemoteBackupError.providerUnavailable` there.
- Added a Keychain-backed trust-on-first-use fingerprint store. It persists a
  fingerprint only after explicit confirmation and rejects a changed pin without
  presenting an automatic replacement path.
- Added the macOS-gated `SFTPRemoteBackupProvider` and connected it through
  `AppCoordinator`. It is deliberately fail-closed before any authentication,
  upload, path inspection, promotion, or verification operation.
- Added contract tests for explicit first-use pinning, changed-pin rejection
  before confirmation/authentication, and rejected first-use non-persistence.

## Security Blocker (Fail Closed)

Citadel 0.12.1 cannot safely implement this task's required transport contract:

1. Its public `NIOSSHPublicKey` API has no stable public serialization or
   fingerprint API. A consumer can compare an in-memory key using Citadel's
   trusted-key validator, but cannot derive and persist/display a SHA-256 host
   fingerprint for deliberate first-use confirmation.
2. Its SFTP client exposes only `rename(at:to:flags:)`; it has no advertised
   atomic no-replace promotion or extension-discovery API. A final-path
   inspection followed by rename remains a race and can overwrite an object.
3. It exposes no server SHA-256 extension/discovery API. Read-back hashing could
   be built after a safe promotion primitive exists, but must not be reached
   while final promotion is unsafe.

The adapter therefore throws `capabilityUnavailable(.noReplacePromotion)` from
preflight before credentials are sent. It does not use `.acceptAnything()`,
does not open an SFTP session, and cannot claim an upload is verified. This is
intentional: replacing a final object or accepting an unverifiable host key
would violate the task's security constraints.

## Validation

- `git diff --check` passed.
- `bash test.sh mac-build` exited 0 after resolving and compiling Citadel 0.12.1.
- `xcodebuild ... build-for-testing -only-testing:BitMatchTests/SFTPRemoteBackupProviderContractTests`
  exited 0. This compiled test targets only; no app, simulator, or test binary
  was launched.
