# BitMatch thesis

Confirmed by Mike, 2026-09-25.

> **BitMatch is a free, open-source card-offload tool: plug in a card, pick your backups, and walk away knowing — with evidence you can hand to anyone — that every backup is a complete, verified copy before you wipe the card.**

Every feature, screen, and refactor should make this truer. When a change is hard to judge, check it against the promises below.

## Promises

1. **The card is sacred.** The source is never modified. Nothing on a destination is overwritten. A partial copy never looks complete.
2. **Green means verified, red means real.** Success only when every file on every backup verified. No false greens, and no false alarms (a Finder `.DS_Store` is not a difference; see GitHub #8).
3. **The evidence matches reality.** Reports, ASC MHL, and history record exactly what happened, built from the same results the screen shows.
4. **Simple by default, powerful on purpose.** The everyday path is: choose a source, choose backups, copy and verify, review the outcome. Photographer jobs, folder recipes, SFTP, ASC MHL, and verification modes are first-class but opt-in; they never crowd the default path.
5. **One app everywhere.** Mac, iPad, and iPhone share the same engine, rules, and verdicts. Layout adapts; behavior does not. Mac-only exceptions (SFTP) are explicit.

## Coherence review, 2026-09-25

A read-only audit of the whole codebase against these promises found the safety core strong and the drift in the layers around it. Findings, in priority order:

- **P5:** Mac and iPad/iPhone are two UI shells over the shared engine. `CopyAndVerifyView`, `CompareFoldersView`, and `MasterReportView` each exist twice, with separate readiness checks. Only about 630 lines of view code are shared.
- **P2:** Operation state is tracked twice: `SharedAppCoordinator.operationState` (the displayed verdict) and `OperationStateService` (pause/resume, which can reject transitions). They can diverge.
- **P5:** macOS alone has `AppCoordinator` (676 lines), which mirrors shared state into five view models by hand. *(Step 3 deletes it; see below.)*
- **P4:** The Mac setup screen shows verification mode and the ASC MHL and report toggles at the top level.
- **Crust:** dead `OperationStateManager` and `MHLGenerator` (kept alive only by their tests); Swift 5 mode with partial strict-concurrency checking; Core Data for jobs next to a JSON journal for transfers; a file-system test stub copied into 7 test files.
- **Test gaps:** no Mac-vs-iOS verdict-parity test; no whole-source-tree-unchanged test.

### Plan: converge, don't rewrite

Each step ships on its own.

1. Delete dead code; correct stale docs and comments.
2. Collapse operation state to one source, with the verdict derived from results. **Done 2026-09-25**, including the typed `ResultOutcome`.
3. Retire `AppCoordinator`: run Mac on `SharedAppCoordinator` as iPad and iPhone do. **Done 2026-09-25.** **Carried out 2026-09-25 on branch `cloud/retire-appcoordinator`** ([plan](superpowers/plans/2026-09-25-retire-appcoordinator.md)): `AppCoordinator` and its four mirrored view models are gone, and the Mac adds only small companions for SFTP, the drive estimate, volume access and camera auto-source. Written without Xcode; done once a Mac build and test run confirm it.
4. Merge the two UI shells one screen at a time, starting with Compare. **Screens done 2026-09-25** (Compare, History, Advanced, Master Report, Outcome, Setup, Progress); the source/backup boxes are still per platform.
5. Extract the engine into a Swift package; adopt Swift 6 strict concurrency.

Target shape: an engine package (`CardSource`, `DestinationWriter`, `ChecksumEngine`, `TransferPipeline`, `TransferJournal`, `EvidenceWriter`) tested against real folders, one `@Observable` app model whose verdict is computed from results, and one adaptive SwiftUI UI. Roughly 40k lines down to 20–24k, almost all of it from removing duplication rather than safety logic.

## Decisions, 2026-09-25

Mike delegated these to the recommendations; the plans in `docs/superpowers/plans/` should follow them.

**Verification (P2)**
- The overall verdict for a Quick transfer stays amber (already the case). Per-file rows say "Copied, not verified" without a green check, and a Quick Compare says "Sizes match, not verified" in amber.
- Paranoid means byte-by-byte comparison plus SHA-256, everywhere (copy, reuse check, and Compare), as the README says.
- The engine writes result text from one typed `ResultOutcome`, and the success rule reads it back through the same type, so the two cannot drift. Older saved text keeps the fail-safe "✅" rule; unknown text is never a success.

**Engine (step 5)**
- iPad and iPhone get a PDF report too (P3, P5); later, low priority.
- Delete `DriveBenchmarkService`; estimate time from observed copy speed.

**UI (step 4)**
- Compare blocks a same-folder or nested compare, and the mode switcher is disabled during any running operation on every platform.
- New transfer clears the source and keeps the backups. Retry and Export appear on the Mac completion screen.
- Cancel asks for one confirmation. The Mac prevents sleep while copying.
- Master Report uses a date picker, defaulting to today.
- One free-space rule everywhere: source size plus 1 GB.
- Choosing Project blocks Start until a card is prepared (the iPad rule).
- The Mac restores last-used backups at launch only when all of them are mounted.

**App state (step 3)**
- iPad and iPhone remember report and camera settings across launches, and use per-card camera-label memory, as the Mac does.
- The Mac's stricter readiness check applies on every platform.

**Step 2 scope additions** (found in the UI plan, section 8): clear `.resuming`; automatic pauses must pause the engine or not claim to; never report an estimated byte count as evidence (the 1,000,000,000 fallback).

## Must fix before the next release

- **Unexplained backup auto-add (seen 2026-09-25).** After the debug stress test set a backup folder in the temp directory, the Mac backups list grew by itself to four: Recovery 2, Macintosh HD, and a `/private/var/folders/...` volume. Safety rules blocked Start. Normal mount and unmount do not reproduce it, `VolumeMonitorService.isBackupDrive` excludes Macintosh HD, and `restoreLastDestinations` runs only on an empty list, so the source is unknown. The stress tool does not start on the pre-pair-2 main, so whether pair 2 introduced it is unknown. Reproduce with a real internal-disk backup folder (the #8 reporter's setup) before release, and add a guard that nothing adds a system or source volume as a backup.
  - **Investigation, 2026-09-25 (branch `cloud/backup-auto-add-investigation`, written without Xcode; still open).** Most likely cause: Mac drive discovery, not restore. `VolumeMonitorService.analyzeVolume` classifies every folder in /Volumes by size alone (512 GiB and up with no camera files is a backup drive) and never calls `isSystemVolume(url)`; `isBackupDrive`, which does, is dead code. /Volumes/Macintosh HD is a symlink to "/", and an APFS volume reports its container's size, so on a 1 TB or larger Mac the startup disk is a "backup drive", and `MacVolumeAccessModel.handleBackupDrivesUpdate` adds every discovered drive that is not already listed or dismissed. "Recovery 2" fits the same path: at launch Disk Arbitration reports every disk and `processDiskAppeared` called `DADiskMount` on each unmounted one, Recovery included; the /Volumes watcher then scanned the new mount without a system check (the name filter matches only "Recovery" exactly). Pair 2 added the one new add path in this area: `restoreLastDestinations` is now called at launch (it was dead before), and the stress test's temp backup had been saved as last-used, which explains the /private/var/folders entry if it was the stress folder itself. Not explained yet: why normal mount and unmount did not show it. Candidates: discovery does not re-add a drive the user removed this session; on a 512 GB Mac the startup disk falls below the size line; and the sandbox may hide /Volumes/Macintosh HD from the scan until the /Volumes bookmark is granted, which rescans. The stress tool's own start never ran on either build: it calls Start straight after setting the source, while the source scan is running, and Start waits for the scan (the one readiness rule, before pair 2), so the stress test says nothing about pair 2.
  - **Guard:** `BackupTargetPolicy` (Shared/Core/Services/File), called by every add path, readiness and the copy preflight. Never allowed: "/" (and so /Volumes/Macintosh HD), anything under /System, the boot volume's root, an internal volume root with a system name ("Recovery 2"), the source's own drive root, any folder on a removable source card (Promise 1). Allowed when picked: a folder on the internal disk (#8), a folder on the source's fixed disk, a folder or disk image in the temp folders (the stress test, the APFS fault harness). Restore also refuses anything in the temp folders and internal volume roots, all or nothing; discovery adds only whole external or removable drives without a system name. BitMatch no longer mounts internal non-removable or system-named disks.
  - **To close:** on the Mac, with a real backup folder on Macintosh HD and a card as source, confirm the list stays as chosen across relaunch, drive plug/unplug and the stress test; confirm the Verbose Dev Logs show "Not a backup drive" for Macintosh HD and any Recovery mount; and check whether "Recovery N" was mounted by BitMatch (`mount` before and after launch on the old build).

