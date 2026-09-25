# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Mac: A connected card that macOS can see but not read now shows a notice instead of nothing. Sony SxS cards point to Sony's SxS UDF Driver, and Sony AXS cards to Sony's AXS reader software.
- Fix: Copying to an exFAT backup drive failed every file with "Destination file appeared during copy; refusing to overwrite it" (0.1.4 through 0.1.6). exFAT has no hard links, which BitMatch used to publish each verified file without any chance of replacing an existing one. On exFAT, BitMatch now claims the file name exclusively and moves the verified copy onto that claim; an existing file is still never replaced.
- Setup: A source or backup not chosen yet is no longer shown as a red "Resolve before starting" error. The next box to fill glows gently (a steady border with Reduce Motion), and Start says what is next, on Mac, iPad and iPhone. The banner is kept for real problems. The separate "Verified copy · SHA-256" line is gone; Advanced lists any changed settings.
- Compare: Works like Setup. The empty folder box to fill next glows (Left first, then Right), and the button says what is next ("Choose the left folder to compare"). The line under the button and the "Checks:" line are gone; Advanced is the same section as on Setup and names a non-default mode. Only same or nested folders still get a warning line. The folder boxes look like Setup's source box, and the clear button has a proper label and hit area.
- Fix: With "Automatically set detected cameras as source" turned on (Mac, off by default), BitMatch could select a card's media subfolder (such as PRIVATE/ on a Sony Alpha or FX3 card) instead of the whole card, leaving the DCIM stills out of a transfer that still verified green. Auto-select now always uses the card root.
- Fix: A transfer's state is stored once, so the screen and pause/resume can no longer disagree. A resumed transfer no longer shows "Resuming" indefinitely, and a transfer that finishes while paused shows how it ended.
- Fix: On iPad and iPhone, switching apps no longer labels a running transfer "Paused" while it keeps copying. Low battery (under 15%) now actually pauses the copy.
- Fix: Report totals (data processed, throughput, average file size) come from the files copied, not an estimate that could read 1 GB when the source had not been measured.
- Fix: Camera detection no longer calls GoPro, DJI, Nikon, Fujifilm, Lumix and Canon video cards "Sony" or "Canon", and now recognises pro cinema cards: Sony VENICE (AXS and SxS), FX6/FX9 XDROOT, XDCAM EX, Canon XF-AVC, ARRI, RED, Blackmagic and Panasonic P2. The Mac card detection, the source label and the iPad/iPhone camera name now come from one set of card-layout rules, so they agree. On iPad and iPhone, a card identified only by brand keeps its folder name (for example GOPRO or SONY), and a card with a known model now gets the same folder name as on the Mac (for example A7SIII rather than A7S3).
- Presentation: Only rows that were checksum- or byte-verified show a green check; a Quick copy's "Copied" rows are neutral. On iPad and iPhone, a cancelled transfer's guidance now says it was cancelled.
- Interface: Mac, iPad and iPhone share one Advanced section for verification mode, ASC MHL and reports. Its label now names only settings changed from their defaults (for example "Quick mode · Reports off") instead of always repeating the mode. iPad and iPhone pick the mode from one menu instead of a nested list with "MHL" badges. The report switch names the formats actually written: "PDF, CSV and JSON" on the Mac, "CSV and JSON" on iPad and iPhone, which write no PDF. Mac Preferences gains the ASC MHL switch that iOS Settings already had. Defaults are unchanged.
- Master Report: Mac, iPad and iPhone find reports with one shared scanner. iPad and iPhone now find the reports BitMatch actually writes (`BitMatch_Report_<date>.json`). A Quick (size-only) copy, or a report that does not say how it was verified, is no longer listed as verified. Both platforms list reports written today (iPad and iPhone used to look back two days), skip reports over 64 MB, and group cards by the card's folder name instead of a guess from the backup path. On the Mac, the report no longer prints the settings' notes as the technician, and no longer says it was generated when saving failed. A report that is too large or can't be read is now named on screen ("2 reports couldn't be read") on every platform, instead of only in the log.
- Transfers: Each transfer shows its state as a word and a symbol (Verified, Needs review, Interrupted, Cancelled, Queued, Copying); only verified transfers are green, and interrupted or issue runs are orange instead of grey. The "review in Transfers" banner is shared by all three platforms and counts interrupted transfers. Row buttons are 44 pt tall on iPad and iPhone and wrap at large text sizes.
- Compare: One Compare screen on Mac, iPad and iPhone. It refuses to compare a folder with itself or with a folder inside it (that always "matched"), waits for folder details before enabling Compare, and says why the button is disabled. Progress, the outcome and Cancel stay on the Compare screen; a finished compare no longer shows the transfer completion screen, and a cancelled or failed compare says so. The verification choice moved under Advanced.
- Compare: A clean Quick compare now says "Sizes match, not verified" in amber instead of "Folders match". Paranoid compare now checks byte-by-byte and SHA-256 (it previously did the byte comparison only).
- Compare: The mode switcher is disabled while a compare, transfer or queue runs, on iPhone too. The cancel notice says "Compare cancelled" or "Transfer cancelled". The Mac accepts dropped folders on either side and explains when a dropped item is not a folder.

## [0.1.6] - 2026-09-25

- Fix: Compare no longer reports "1 only in destination" after an offload when Finder has written a .DS_Store into the copied folder. Finder view files (.DS_Store, ._*, Icon) are ignored on both sides, and checksum manifests written at the destination root (ascmhl/, .mhl, .mhl.md5) no longer count as extra files (GitHub issue #8).

## [0.1.5] - 2026-09-21

- Camera detection: Fix scan/detection races across unmount and same-path remount (per-volume generations, tombstones, owned request handles); a rescan while monitoring is stopped no longer publishes.
- Compare: iPhone and iPad use the real document picker; cancelling any folder picker preserves the existing selection.
- Responsiveness: Mac folder enumeration, camera-hint detection, and camera label memory detection run off the main actor with cancellation and stale-result guards.
- Cancellation: Camera detection honors task cancellation at stage boundaries, inside enumeration loops, and at metadata subprocesses (terminated on cancel, bounded wait); camera memory store is lock-guarded.
- Outcomes: Cancelled operations keep visible partial results on Mac, iPhone, and iPad with explicit cancelled wording.
- Destinations: Volume rediscovery no longer re-adds an explicitly removed destination until the drive is unplugged or re-added.
- Cleanup: Remove dead async utilities, regex helper, and unused test mocks; report exports log through the shared logger.

- Interface: Simplify transfer setup and completion, keep optional controls under Advanced, and show a result for each backup on Mac, iPad, and iPhone.
- ASC MHL: Create initial ASC MHL 2.0 inventories after SHA-256 verification; validate generated manifests and chains with the official reference tooling. Existing histories are preserved and reported as unsupported, never overwritten or presented as extended.
- Recovery: Add a persistent local transfer queue, interrupted-attempt recovery, searchable history, and JSON/CSV exports across all three platforms. Queue entries retain independent settings and original folder identities; issues stop the queue.
- Completion: Keep unverified copies and failed handoff records out of the successful verdict. Preserve complete file results for review and export.

- Usability: Clarify source and backup selection, explain verification modes, show all preflight issues, and add next-step guidance beside Start and after completion.
- Usability: Rename the one-time workflow to avoid confusion with Quick verification; preserve distinguishing suffixes in long destination names.
- Testing: Retain fault/soak evidence and support reusable build directories without modifying their generated test configurations.
- Documentation: Refresh the public README and screenshots; add a hardware validation register, reporting template, and GitHub hardware-test form.

## [0.1.4] - 2026-09-03

- Fix: Read free space correctly on exFAT/FAT destinations; the APFS-only "important usage" capacity reports 0 there, which wrongly aborted transfers with "Insufficient space: 0.0GB available" (GitHub issue).
- Fix: Skip macOS volume metadata folders (.Spotlight-V100, .fseventsd, .Trashes, .TemporaryItems, .DocumentRevisions-V100) when reading a card, so offloads no longer fail with a permission error without Full Disk Access (GitHub issue).
- Fix: Preserve nested folder structure when the source or destination path is reached through a symlink or the /private alias; previously nested files could be flattened to their bare names.
- Fix: A destination that cannot be pinned when its turn comes (for example, permissions changed after preflight) now reports its files as failed and lets other destinations continue. Preflight failures and safety rejections still abort the whole transfer, and cancellation is never recorded as a destination failure.
- Fix: Cancellation again waits for verifier cleanup, and the operation's injected file-system and checksum services are exercised on the pinned copy path while destination reads stay descriptor-pinned.
- Fix: Core Data readiness callbacks fire together with store availability; coordinator bindings no longer invalidate a prepared card on launch.
- Photographer jobs: Add persistent job, photographer, camera, and card identities with reusable folder recipes and preserved local card packages.
- Safety: Require exact verified local-copy manifests before a card becomes locally safe, and surface duplicate-card fingerprint warnings without discarding sidecars or failed rows.
- Reporting: Add photographer-aware PDF, CSV, and enhanced JSON provenance with package paths, companion counts, fingerprints, exact-copy evidence, warnings, and complete authoritative results.

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
