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
- **P5:** macOS alone has `AppCoordinator` (676 lines), which mirrors shared state into five view models by hand.
- **P4:** The Mac setup screen shows verification mode and the ASC MHL and report toggles at the top level.
- **Crust:** dead `OperationStateManager` and `MHLGenerator` (kept alive only by their tests); Swift 5 mode with partial strict-concurrency checking; Core Data for jobs next to a JSON journal for transfers; a file-system test stub copied into 7 test files.
- **Test gaps:** no Mac-vs-iOS verdict-parity test; no whole-source-tree-unchanged test.

### Plan: converge, don't rewrite

Each step ships on its own.

1. Delete dead code; correct stale docs and comments.
2. Collapse operation state to one source, with the verdict derived from results.
3. Retire `AppCoordinator`: run Mac on `SharedAppCoordinator` as iPad and iPhone do.
4. Merge the two UI shells one screen at a time, starting with Compare.
5. Extract the engine into a Swift package; adopt Swift 6 strict concurrency.

Target shape: an engine package (`CardSource`, `DestinationWriter`, `ChecksumEngine`, `TransferPipeline`, `TransferJournal`, `EvidenceWriter`) tested against real folders, one `@Observable` app model whose verdict is computed from results, and one adaptive SwiftUI UI. Roughly 40k lines down to 20–24k, almost all of it from removing duplication rather than safety logic.
