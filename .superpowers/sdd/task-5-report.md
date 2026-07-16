# Phase 2 Task 5 Report: Secure OpenSSH SFTP Provider

## Implemented

- Removed Citadel and its transitive Swift Package lockfile. The provider is a
  macOS-only OpenSSH adapter; the shared iPad factory remains typed unavailable.
- Added profile-private application-support `known_hosts` paths. A first-use
  attempt runs `ssh-keyscan` followed by `ssh-keygen -lf - -E sha256`, presents
  the captured SHA-256 fingerprint through an injected confirmation boundary,
  and persists the exact scanned entries only after that boundary returns true.
  Missing confirmation, unknown hosts, and changed keys fail closed before SSH
  agent authentication or SFTP transfer.
- Every SSH/SFTP command fixes `StrictHostKeyChecking=yes`, `BatchMode=yes`, a
  profile-private `UserKnownHostsFile`, disabled password and
  keyboard-interactive methods, and `PreferredAuthentications=publickey`.
  Password-bearing `RemoteCredential` values are rejected; `.sshAgent` carries
  no secret material.
- SFTP handles upload/resume and read-back. SSH is invoked with `-T` only for
  remote POSIX operations: contained directory creation, byte inspection, and
  atomic no-replace `ln temporary final && rm temporary`. A final-exists error
  is a conflict; a shell/command failure is a capability failure, never success.
- Added command-construction/classification coverage for strict options,
  SFTP's lack of SSH `-l`, POSIX single-quote escaping, and `ln` conflict
  classification. Remote path components now reject control characters.
- Added `com.apple.security.network.client` to the macOS entitlement.

## Remaining Limits

- The application has no Task 6 UI yet to supply the first-trust confirmation;
  the default factory intentionally supplies no confirmer and therefore blocks
  unknown hosts with `hostKeyMismatch`. A caller must present the injected
  SHA-256 request to the user before agent authentication can proceed.
- POSIX shell availability is a required remote capability. Restricted-shell or
  SFTP-only accounts fail closed rather than attempting a racy SFTP rename.

## Validation

- `git diff --check` passed.
- `bash test.sh mac-build` exited 0 after compiling the OpenSSH provider on
  2026-07-15. No app, simulator, tests, or test binary was launched.
