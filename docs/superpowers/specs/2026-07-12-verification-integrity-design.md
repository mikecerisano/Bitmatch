# Verification Integrity Design

Date: 2026-07-12
Status: Approved for implementation

## Purpose

Make every BitMatch success verdict depend on one complete, stable, operation-scoped result set. Cancellation, UI delivery, report generation, and filesystem errors must never turn a failed or incomplete verification into success.

## Scope

This project fixes the release-blocking integrity defects found in the full codebase review:

- file-result delivery can lag behind completion;
- cancelled verifier tasks can outlive their operation;
- repeated starts can overlap during preflight or cancellation;
- directory enumeration can return a partial manifest without an error;
- checksum and byte comparison can miss file growth during a read;
- iPad completion and macOS PDF status can ignore failed rows;
- large failure sets can crash the macOS results view.

Later projects will finish iPad reports and comparison, implement durable crash recovery and MHL, correct report metrics, and remove dead architecture. Those changes remain outside this project's code path unless a small compatibility edit is required.

## Approaches Considered

### Patch each presentation bug independently

This approach would change the iPad header, PDF filter, and results table without changing operation ownership. It would improve visible symptoms but leave late callbacks and stale verifier tasks able to corrupt the underlying verdict. Rejected.

### Replace the transfer stack with a new session actor

A new actor could own manifests, scopes, results, pause state, verification tasks, and reports. This is the clean long-term boundary, but replacing the complete transfer stack in one change would put the proven atomic-copy path at unnecessary risk. Deferred.

### Strengthen the current operation boundary

The selected approach preserves the existing copy engine while making its boundaries explicit. Each operation will own its verification tasks, callbacks will be awaited, the returned `FileOperation.results` will be authoritative, enumeration will throw on incomplete traversal, and the coordinator will reject a new start until cancellation has finished. This approach removes the false-success paths with focused changes and regression tests.

## Invariants

The implementation must preserve these rules:

1. A transfer reaches success only after every result callback has finished.
2. The final verdict and report use `FileOperation.results`, not a presentation cache.
3. No verifier task survives its operation's success, failure, or cancellation.
4. A new operation cannot replace an active or cancelling operation.
5. Root, traversal, and metadata enumeration errors fail the operation.
6. Verification rejects a file that grows, shrinks, or changes identity while read.
7. Every UI and PDF issue count uses `ResultRow.isSuccessStatus` over all result rows.
8. Existing atomic-write, no-overwrite, pause, security-scope, and destination-layout behavior remains intact.

## Manifest Enumeration

`FileTreeEnumerator` will return a throwing manifest. It will install an enumeration error handler, surface root and subtree errors, and throw metadata-read failures instead of skipping entries. `SharedFileOperationsService` will build this manifest once and use it for file count, byte count, copy input, and verification input.

Comparison filesystem services will also distinguish an empty folder from an unavailable or unreadable folder. A valid empty directory remains a valid manifest.

## Stable Verification

Checksum generation and byte comparison will validate the complete read:

- capture the initial file identity, size, and modification date;
- open the file and read the expected content;
- read once more to prove EOF;
- capture final identity, size, and modification date;
- reject any changed snapshot.

Pair verification will revalidate both source and destination after both reads. Live transfer verification will continue to bypass the persistent checksum cache.

## Ordered Results and Completion

The file-result callback contract will become asynchronous. `SharedFileOperationsService` will await each callback before it can finish. `CopyVerifyExecutor` will update presentation storage on MainActor without spawning an untracked task.

The returned `FileOperation.results` will drive issue counts, completion status, reports, and the final UI snapshot. `ResultsOverflowService` remains a presentation and large-list aid; its contents cannot determine transfer success.

## Cancellation and Start Ownership

`SharedFileOperationsService` will keep each verifier handle in an operation-local store. Every exit path will cancel and await remaining handles before releasing security scopes or clearing the checksum pause hook.

The service will reject overlapping operations instead of cancelling an existing operation implicitly. `SharedAppCoordinator` will set its start latch before the first asynchronous preflight call and keep it set until execution or cancellation fully unwinds. Cancellation may publish a cancelling or cancelled state, but it must not enable Start early.

Callbacks will remain bound to their operation. A stale operation cannot write into a later operation's result storage or state.

## Truthful Presentation

The iPad completion header will derive its title, icon, and color from the completed operation state and failed result rows. Error-report diagnostics remain supplementary.

The PDF will calculate success and issues over every row. It may present a media-focused preview, but filtering must not remove failures from the verdict or issue section.

The macOS results view will cap visible rows without passing a negative length to `suffix`. Failed rows will remain visible within the cap.

## Error Handling

New enumeration, stable-read, overlapping-operation, and result-delivery errors will fail closed. Messages will name the affected file or root and explain that BitMatch refused to certify an incomplete result.

Cancellation remains distinct from failure. Cleanup errors must not erase the original cancellation or verification error, but they must be logged with the operation identifier.

## Test Strategy

Each behavior will follow red-green-refactor development. Regression tests will cover:

- a final mismatch emitted immediately before the file service returns;
- cancellation with a blocked verifier, followed by an attempted restart;
- missing roots and injected subtree enumeration errors;
- source and destination growth during checksum and byte comparison;
- iPad completion with failed rows but no diagnostic error;
- a PDF model containing successful media and a failed sidecar;
- more than 1,000 failed result rows.

The final gate includes the full macOS suite, iPad tests, both Release builds, a strict-concurrency diagnostic build, and the seeded two-destination soak.

## Completion Criteria

This project is complete when all listed regressions fail before their implementation, pass afterward, and the full verification gate succeeds. The branch must contain no generated DerivedData, result bundles, temporary reports, or soak fixtures.
