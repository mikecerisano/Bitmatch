# What this diff claims to do (lead's summary for reviewers)
Base ef66597 (main, 2026-08-12). 13 commits. All macOS tests pass (458) and iPad builds.
1. SafetyValidator: exFAT/FAT report volumeAvailableCapacityForImportantUsage as 0, not nil; fall back to standard capacity (GitHub #6).
2. FileTreeEnumerator: skip .Spotlight-V100/.fseventsd/.Trashes/.TemporaryItems/.DocumentRevisions-V100 (GitHub #7); compute relative paths robustly across the /var vs /private/var alias and THROW instead of flattening to lastPathComponent.
3. FileCopyService: relativePath prefix comparison resolved on both sides (nested files were flattened); verifyPinnedDestinationFile/checksumVerification take the operation's injected ChecksumService for the SOURCE digest only; destination digest must still read through the pinned descriptor in every mode.
4. SharedFileOperationsService: per-destination setup isolated so one inaccessible destination fails its files and continues; FileOperationError (safety rejections) still aborts the whole operation; destination root pre-created via injected fileSystem.createDirectory before PinnedDestinationDirectory.open; Task.checkCancellation before that.
5. BitMatchPersistenceController: finish synchronous store loads inline on the main actor so isStoreLoaded and whenStoreReady observers flip together.
6. AppCoordinator: dropFirst() on $sourceURL subscription to skip Combine's initial nil replay that invalidated prepared cards.
7. Tests: OperationOwnership doubles gate generateChecksum; TransferFaultIntegration source-mutation test triggers via onFileResult instead of a checksum double; two fixture corrections; one expected string aligned to the presentation-owned blocker.
