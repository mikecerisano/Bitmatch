# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.3] - 2026-07-13
- Safety: Reject files that grow, shrink, or change identity during checksum or byte verification, including mismatch paths.
- Safety: Build one fail-closed source manifest and use it for preflight counts, bytes, copying, verification, and final results.
- Reliability: Make result delivery ordered and authoritative; keep exact operation ownership through cancellation and cleanup.
- Reporting: Derive completion verdicts, counts, issue groups, throughput, sizes, and extension breakdowns from every result, including sidecars.
- UX: Simplify Mac and iPad transfer setup with explicit preflight state, blockers, verification choices, and accessible readiness guidance.
- Architecture: Remove orphaned operation layers and centralize shared coordinator bindings and iOS background-task ownership.
- Testing: Add deterministic fixtures, transfer fault injection, seeded soak coverage, strict-concurrency builds, and GitHub CI for macOS tests and iPad builds.
- Design: Refresh the application icon and retain the native, restrained utility interface.

## [0.1.2] - 2026-07-01
- Safety: Fix exported PDF/CSV/JSON reports counting "Checksum Mismatch" and "Size Mismatch" rows as verified matches; status classification now has a single fail-safe rule (`ResultRow.isSuccessStatus`) used by reports, the executor, and view models.
- Safety: Master reports no longer mark transfers "verified" when they completed with failures; Compare mode completes with success only when both folders truly match.
- Safety: Fix a race where an out-of-order "Copied" row could replace a checksum-mismatch row in the results store; result rows now upsert atomically and copy-stage rows can never supersede verify results.
- Safety: Checksum reads now use throwing file reads (a failing card surfaces as a per-file error instead of crashing), refuse to return a checksum when the file shrank mid-read, and Paranoid byte comparison errors promptly instead of hanging on truncated files.
- Recovery: Crash-resume detection now decodes its persisted timestamps correctly, records total counts in checkpoints, and clears completed operation state.
- Stability: Starting a new copy/verify operation clears any stale pause flag so a previously paused run cannot block the next transfer.
- iOS: Compare mode now keeps security-scoped access alive across folder enumeration, size reads, and checksum/byte verification.
- iOS: Retain the Master Report drive picker delegate until selection or cancellation so the document picker continuation cannot be stranded.
- MHL: Remove the uncalled results-to-MHL path that could emit placeholder checksums, reject entries outside the destination manifest, and generate per-destination MHL files for multi-destination transfers.
- Tests: Add regressions for status classification, master-report verified flags, out-of-order result rows, mid-read file truncation, crash-resume detection, stale pause flags, Compare security-scope lifetime, iOS picker delegate retention, and MHL destination integrity.

## [0.1.1] - 2026-05-25
- Safety: Quick mode no longer reuses or pre-counts existing destination files because size and mtime alone cannot prove equality.
- Docs: Update README safety wording to distinguish checksum-verified reuse from Quick mode.
- Development: Make `test.sh` run the contributor-friendly macOS unit target with explicit project, destination, and unsigned build settings.
- Safety: Align drop-zone system-path validation with transfer safety validation for temporary scratch paths.
- Safety: Make automatic report, checksum, and MHL export filenames collision-safe.
- Safety: Validate resolved output folders before any destination directory creation in all copy entry points.
- Safety: Publish copied temp files with a non-overwriting move so destination races fail instead of replacing an existing item.
- Safety: Remove automatic cleanup scans that deleted matching temp/junk files from user folders or mounted volumes.
- Safety: Detect source write protection from volume metadata instead of creating a probe file on the source volume.
- Privacy: Remove opt-in network analytics sharing and community baseline fetching so BitMatch has no app analytics upload path.
- Release: Guard debug-only stress-test and fake-transfer UI call sites so the Release configuration compiles.
- Safety: Make first-run verification default to Standard SHA-256 instead of Quick mode.
- Safety: Add shared-core validation for final resolved destination roots, including duplicates, nesting, source containment, symlinked roots, and file-vs-folder conflicts.
- Safety: Add source-tree preflight for unsafe relative paths and case/Unicode-normalized filename collisions before any copy writes begin.
- Safety: Rework copy behavior to avoid destructive overwrites; existing files are reused only when proven identical.
- Safety: Copy hidden files and preserve empty folders while continuing to skip symlink entries.
- Safety: Detect source mutation during copy and refuse to publish the destination file.
- Verification: Use uncached checksums for live copy/verify/report paths and byte-by-byte comparison for Paranoid mode.
- Reporting: Preserve large result sets and coalesce spilled copy/verify rows so final reports keep the latest status per file/destination.
- UX: Add readiness warnings for Quick mode and unsafe final output roots.
- Tests: Add regressions for destination conflicts, hidden files, empty folders, source mutation, portable path collisions, paranoid verification, result retention, and overflow report coalescing.
- Performance: Add cross-platform persistent checksum cache (actor-based, 1h TTL) with disk persistence; integrated into SharedChecksumService.
- Performance: Move folder info enumeration off the main actor to prevent UI stalls on large folders.
- Performance: Parallelize destination folder info updates with a conservative concurrency cap.
- iOS: Optimize security-scoped resource usage by using a single folder scope and per-file fallback only when required.
- Logging: Consolidate logging by forwarding `AppLogger` to `SharedLogger` for consistent output across platforms.
- Cleanup: Remove legacy `#if false` files and obsolete macOS shim; re-added a minimal shim under the mac target path to fix target resolution until full migration.
- Stability: Remove force-unwrap in iOS PDF generation (`SharedReportGenerationService`) by making the renderer content method non-throwing.
- Stability: Replace `try!` in regex matching (`CameraStructureDetector`) with safe `do/try` handling.
- Diagnostics (iOS): Add DEBUG timing logs to `IOSFileSystemService.getFileList` to report enumeration time and per-file scope fallbacks.

## [2025-09-07]
- Architecture: Shared core services finalized and integrated across iPad and macOS targets.
- iPad: Modular UI with `SharedAppCoordinator` and professional layouts.
- Reporting: Unified PDF/JSON generation via `SharedReportGenerationService` with platform-specific rendering helpers.
- State/Timing: Integrated `OperationStateService` and `OperationTimingService` for pause/resume and rich telemetry.
