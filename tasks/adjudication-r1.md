# Lead adjudication, round 1 (2026-09-03)
Seats: codex gpt-5.6-terra (BLOCK), GLM 5.3 (BLOCK), Gemini/agy (BLOCK). Adjudicated on substance, not votes.

## Accepted as blockers (fix before release)
B1. Path-based pre-create before pinning (codex B1, gemini B4, GLM NB4). Real TOCTOU weakening: FileManager.createDirectory follows a planted symlink and writes outside the destination before the O_NOFOLLOW walk rejects. It existed only as a test seam. FIX: remove it; add an explicit, non-writing `destinationSetupHook` init parameter (nil in production) that OperationOwnershipTests uses to block/fail destination setup.
B2. Volume-metadata skip applies at every depth (codex B2). A user folder named .Trashes etc. nested anywhere would be silently omitted from the manifest. FIX: skip only direct children of the source root (enumerator.level == 1); test nested-name retention.
B3. Per-destination catch swallows CancellationError (GLM B1, gemini B2). Cancel during destination setup would fabricate files x destinations failure rows and continue. FIX: rethrow CancellationError ahead of the generic catch; test that cancel during setup throws with zero result rows.
B4. FileCopyService and SafetyValidator.validateSourceTreeForCopy still flatten to lastPathComponent on prefix mismatch (gemini B1, codex note, GLM NB1/NB2). FIX: one shared throwing resolver in FileTreeEnumerator used by enumerator, both copy variants, directory pre-pass, and the portable-path validator; per-file failures report through onError instead of flattening.
B5. Core Data async completion still exposes isStoreLoaded before observers (codex NB3, accepted as a fix since it's the same invariant). FIX: isStoreLoaded requires finishStoreLoad to have run.

## Overruled in writing
O1. Gemini B3 "POSIXError(.ELOOP) treated as inaccessible": false. PinnedDestinationDirectory maps ELOOP and ENOTDIR-on-symlink to FileOperationError.unsafeOperation (FileCopyService.swift:127-128, 171-172), which the isolation catch rethrows. No change.
O2. Gemini "result poisoning across destinations": false. ResultStore keys on (sourceURL, destinationURL) (SharedFileOperationsService.swift:5-22). No change.
O3. Gemini B3-style "silent success when all destinations fail": completion derives the verdict from failure rows (codex confirmed). No change.
O4. APFS capacity fallback lacks volume-type guard (codex NB4, gemini NB2, GLM). On APFS the important-usage figure includes purgeable space and is never below the standard figure in practice, so a zero there implies a zero standard figure; and the second gate (fileSystem.freeSpace, 100 MB headroom) already uses the standard figure. Accepted risk; noted as a follow-up test on real APFS.
O5. dropFirst on $sourceURL (GLM, gemini NB1): codex found no macOS path that assigns a source before bindings and iPad uses SharedAppCoordinator. Kept.

## Non-blocking follow-ups (not in this release)
F1. Progress counters do not advance for an isolated failed destination (codex NB2).
F2. Duplicate ResultStore rows when pipelining is disabled and source path is aliased (codex NB1); pre-existing.
F3. Duplicate space gates with different headroom (GLM NB6); pre-existing.
F4. .DS_Store still copied (GLM NB7); pre-existing behavior, product decision.
F5. Changelog overstated isolation scope (GLM NB5): reworded now.
