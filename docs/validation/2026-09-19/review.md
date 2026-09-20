# Follow-up review of the release-readiness implementation

Reviewed `08b34ba..44d1a77` with three Luna reviewers and an integration review. The implementation addresses the right workflows and adds useful regression coverage. This follow-up fixes interactions that the original checks missed.

## Fixed

- **Comparison evidence could describe the wrong run.** Changing the verification mode could relabel a Quick result as Standard; Mac folder selection changes did not clear the shared result. Results now clear when selection or mode changes, and in-flight results are discarded if their inputs changed. Quick results explicitly describe size checks. Export timestamps are labeled `exportedAt`.
- **Comparison paths could lose their directory.** Canonical relative-path resolution replaces the basename fallback, including `/private` aliases and rejection of paths outside the selected root.
- **Volume metadata was inspected before it was excluded.** Preflight, manifest enumeration, and both directory-copy walkers now identify root metadata directories before loading Foundation attributes. Ordinary files with the same names and nested folders remain included.
- **Reconnect was incomplete.** Queued transfers now offer Reconnect. Partial identities cannot authorize a replacement folder; the UI explains when identity cannot be confirmed. Reauthorized locations must be readable directories. Terminal attempts with no file results can still export their JSON record.
- **Automatic exports could outlive completion.** The checksum manifest is now part of the awaited, throwing export path on both platforms. It preserves recorded checksums and full destination paths instead of re-reading files after the transfer lease ends. JSON and CSV also retain per-file checksums and sizes. Cancellation during finalization remains cancelled, and mobile completion controls wait for journal finalization.
- **Remote work could get stranded or leave stale summaries.** The scheduler serializes drains, handles requests arriving during a drain, waits for the production store to become available, and schedules overdue backoff deadlines. Startup and timer-driven work refresh the owning project's summaries without changing the current project; separate remote destinations retain separate summaries. Queue-control errors reach the user.
- **Pause/retry could lose promotion ownership.** A durable promotion marker survives pause and retry exhaustion. Run generations reject delayed callbacks from invalidated workers. Existing final files still require proven promotion ownership and matching verification evidence.
- **The recorded path-traversal test failure is fixed.** Drop validation rejects raw parent-directory components without double-decoding literal percent-encoded names.

## Validation

- `bash test.sh mac-test`: passed, **537 executions / 518 unique tests, zero failures, two skips**. The skips remain the opt-in soak test and the case-sensitive-filesystem metadata collision test. See [the summary](review-test-summary.json).
- `bash test.sh ipad-build`: passed during review.
- Final `bash test.sh release-builds`: Mac and shared iPhone/iPad simulator Release builds passed with code signing disabled.
- `git diff --check`: passed.

Regression coverage includes stale comparison inputs, metadata-named ordinary files, incomplete folder identity, retained report evidence, cancellation before reporting, background project summaries, promotion recovery, stale provider errors, and an AppCoordinator scheduler integration test.

## Limits

These are source, unit/integration, and build checks. No new interactive screenshots, physical-device transfers, real SFTP-server tests, or receiving-tool ASC acceptance tests were recorded. Report failures can leave partial report files, but completion and history retain the failure. Remote pause takes effect at worker checkpoints; bytes can still reach a provider before it stops, and offset disagreements remain fail-closed. A persistent queue-store write failure can still require manual recovery; this review does not claim automatic recovery from unavailable storage.

The public download remains v0.1.4. This review does not sign, notarize, or publish a new binary. GitHub Actions remains disabled as requested.
