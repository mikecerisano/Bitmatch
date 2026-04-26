# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
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
