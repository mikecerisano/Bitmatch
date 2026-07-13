# Verification Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BitMatch fail closed and derive every success verdict from a complete, stable, operation-scoped result set.

**Architecture:** Preserve the atomic copy engine and strengthen its boundaries. Build one throwing source manifest, verify stable file snapshots, await result delivery, make `FileOperation.results` authoritative, own verifier tasks through cleanup, and centralize result presentation rules.

**Tech Stack:** Swift 5, Swift Concurrency, Foundation, SwiftUI, XCTest, Swift Testing, Xcode 16.

## Global Constraints

- A transfer reaches success only after every result callback has finished.
- The final verdict and report use `FileOperation.results`, not a presentation cache.
- No verifier task survives its operation's success, failure, or cancellation.
- A new operation cannot replace an active or cancelling operation.
- Root, traversal, and metadata enumeration errors fail the operation.
- Verification rejects a file that grows, shrinks, or changes identity while read.
- Every UI and PDF issue count uses `ResultRow.isSuccessStatus` over all result rows.
- Existing atomic-write, no-overwrite, pause, security-scope, and destination-layout behavior remains intact.
- Every behavior change follows red-green-refactor: add the regression, observe its expected failure, implement the minimum correction, and rerun the covering tests.
- Both app targets must continue to build without generated artifacts entering git.

---

### Task 1: Reject files that grow or change during verification

**Files:**
- Modify: `BitMatchTests/ChecksumTruncationTests.swift`
- Modify: `Shared/Core/Services/SharedChecksumService.swift`

**Interfaces:**
- Consumes: `ChecksumService.generateChecksum` and `ChecksumService.performByteComparison` without signature changes.
- Produces: a private immutable `FileReadSnapshot`, `captureSnapshot(for:)`, and `validateStableRead(of:initial:bytesRead:trailingData:)` inside `SharedChecksumService`.

- [ ] **Step 1: Add failing growth regressions**

Add helpers and two tests to `ChecksumTruncationTests`:

```swift
private func appendByte(to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0xff]))
}

func testChecksumThrowsWhenFileGrowsAfterFinalChunk() async throws {
    let file = try makeFile("growing-hash.bin", size: 64 * 1024)
    let appended = ThreadSafeFlag()

    do {
        _ = try await SharedChecksumService.shared.generateChecksum(
            for: file,
            type: .sha256,
            useCache: false
        ) { [self] progress, _ in
            if progress >= 1, !appended.getAndSet() {
                try? appendByte(to: file)
            }
        }
        XCTFail("Expected checksum of a growing file to throw")
    } catch {
        XCTAssertTrue(error.localizedDescription.contains("changed while reading"))
    }
}

func testByteComparisonThrowsWhenFileGrowsAfterFinalChunk() async throws {
    let source = try makeFile("growing-source.bin", size: 64 * 1024)
    let destination = try makeFile("growing-destination.bin", size: 64 * 1024)
    let appended = ThreadSafeFlag()

    do {
        _ = try await SharedChecksumService.shared.performByteComparison(
            sourceURL: source,
            destinationURL: destination
        ) { [self] progress, _ in
            if progress >= 1, !appended.getAndSet() {
                try? appendByte(to: source)
            }
        }
        XCTFail("Expected byte comparison of a growing file to throw")
    } catch {
        XCTAssertTrue(error.localizedDescription.contains("changed while reading"))
    }
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-1 \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/ChecksumTruncationTests
```

Expected: both new tests fail because current loops stop at the initial size and return a digest or `true`.

- [ ] **Step 3: Implement stable read snapshots**

Add a private snapshot model that reads size, modification date, and inode from `FileManager.attributesOfItem`. Capture it before opening each file. After the expected bytes are read, read one extra byte and capture the snapshot again.

```swift
private struct FileReadSnapshot: Equatable {
    let size: Int64
    let modificationDate: Date?
    let systemFileNumber: UInt64?
}

private func captureSnapshot(for url: URL) throws -> FileReadSnapshot {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return FileReadSnapshot(
        size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
        modificationDate: attributes[.modificationDate] as? Date,
        systemFileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
    )
}

private func validateStableRead(
    of url: URL,
    initial: FileReadSnapshot,
    bytesRead: Int64,
    trailingData: Data
) throws {
    let final = try captureSnapshot(for: url)
    guard bytesRead == initial.size, trailingData.isEmpty, final == initial else {
        throw NSError(
            domain: "SharedChecksumService",
            code: -11,
            userInfo: [NSLocalizedDescriptionKey: "File changed while reading \(url.lastPathComponent)"]
        )
    }
}
```

Use this validation in MD5, SHA-1, SHA-256, and byte comparison. Pair verification must capture source and destination before either hash and confirm both snapshots again after both hashes.

- [ ] **Step 4: Run focused and related checksum tests**

Run the Task 1 command, then:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-1-related \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/SharedChecksumServiceTests \
  -only-testing:BitMatchTests/SharedChecksumByteCompareTests \
  -only-testing:BitMatchTests/SharedChecksumEdgeCaseTests
```

Expected: all tests pass; stable files retain their existing digests.

- [ ] **Step 5: Commit**

```bash
git add BitMatchTests/ChecksumTruncationTests.swift Shared/Core/Services/SharedChecksumService.swift
git commit -m "fix: reject files that change during verification"
```

---

### Task 2: Build one fail-closed source manifest

**Files:**
- Create: `BitMatchTests/FileTreeEnumeratorTests.swift`
- Modify: `Shared/Core/Services/File/FileTreeEnumerator.swift`
- Modify: `Shared/Core/Services/SharedFileOperationsService.swift`
- Modify: `BitMatch/Core/Services/Platform/MacOSFileSystemService.swift`
- Modify: `Platforms/iOS/Services/IOSFileSystemService.swift`

**Interfaces:**
- Produces: `FileTreeEnumerator.enumerateRegularFiles(base:) throws -> [FileEntry]`.
- Removes: the separate nonthrowing `countRegularFiles(base:)` production pass.
- Preserves: valid empty folders return an empty manifest.

- [ ] **Step 1: Add failing manifest regressions**

Create `FileTreeEnumeratorTests.swift`:

```swift
import XCTest
@testable import BitMatch

final class FileTreeEnumeratorTests: XCTestCase {
    func testMissingRootThrowsInsteadOfReturningEmptyManifest() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-manifest-\(UUID().uuidString)")
        XCTAssertThrowsError(try FileTreeEnumerator.enumerateRegularFiles(base: missing))
    }

    func testValidEmptyRootReturnsEmptyManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(try FileTreeEnumerator.enumerateRegularFiles(base: root).isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-2 \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/FileTreeEnumeratorTests
```

Expected: the missing-root test fails because the existing enumerator returns `[]`.

- [ ] **Step 3: Make enumeration throw**

Change the entry point to a throwing function. Validate the root, capture the first `DirectoryEnumerator` error, throw metadata errors, and check cancellation:

```swift
static func enumerateRegularFiles(base: URL) throws -> [FileEntry] {
    let fileManager = FileManager.default
    let basePath = base.path
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
    var entries: [FileEntry] = []
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: base.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw BitMatchError.fileNotFound(base)
    }

    var traversalError: Error?
    guard let enumerator = fileManager.enumerator(
        at: base,
        includingPropertiesForKeys: Array(keys),
        options: [],
        errorHandler: { url, error in
            traversalError = NSError(
                domain: "FileTreeEnumerator",
                code: (error as NSError).code,
                userInfo: [NSLocalizedDescriptionKey: "Could not read \(url.lastPathComponent): \(error.localizedDescription)"]
            )
            return false
        }
    ) else {
        throw BitMatchError.fileAccessDenied(base)
    }

    while let item = enumerator.nextObject() as? URL {
        try Task.checkCancellation()
        let values = try item.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true || values.isRegularFile != true {
            continue
        }
        let relativePath = item.path.hasPrefix(basePath + "/")
            ? String(item.path.dropFirst(basePath.count + 1))
            : item.lastPathComponent
        entries.append(FileEntry(
            url: item,
            relativePath: relativePath,
            size: Int64(values.fileSize ?? 0)
        ))
    }
    if let traversalError { throw traversalError }
    return entries
}
```

Delete `countRegularFiles(base:)`; do not retain a nonthrowing fallback.

- [ ] **Step 4: Use the manifest as the transfer authority**

At the start of the transfer preparation stage, build one manifest:

```swift
let sourceManifest = try FileTreeEnumerator.enumerateRegularFiles(base: operation.sourceURL)
let perSourceFileCount = sourceManifest.count
let manifestBytes = try sourceManifest.reduce(Int64(0)) { total, entry in
    let (sum, overflow) = total.addingReportingOverflow(max(0, entry.size))
    guard !overflow else {
        throw FileOperationError.unsafeOperation("Source size exceeds the supported range")
    }
    return sum
}
let totalSizeBytes = operation.estimatedTotalBytes ?? manifestBytes
```

Pass `sourceManifest.map(\.url)` into every destination copy and use the same entries during verification. Remove the separate count, size, and pre-enumeration walks.

Update macOS and iOS `getFileList` implementations so a missing root, a nil enumerator, an enumeration callback error, or a metadata error throws. Keep security scopes balanced on iOS.

- [ ] **Step 5: Run manifest, transfer, and comparison tests**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-2-green \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/FileTreeEnumeratorTests \
  -only-testing:BitMatchTests/SharedFileOperationsServiceTests \
  -only-testing:BitMatchTests/SharedFileOperationsEdgeCaseTests \
  -only-testing:BitMatchTests/SharedCompareFlowTests
```

Expected: all tests pass, including hidden files and valid empty directories.

- [ ] **Step 6: Commit**

```bash
git add BitMatchTests/FileTreeEnumeratorTests.swift \
  Shared/Core/Services/File/FileTreeEnumerator.swift \
  Shared/Core/Services/SharedFileOperationsService.swift \
  BitMatch/Core/Services/Platform/MacOSFileSystemService.swift \
  Platforms/iOS/Services/IOSFileSystemService.swift
git commit -m "fix: fail closed when source enumeration is incomplete"
```

---

### Task 3: Make ordered operation results authoritative

**Files:**
- Create: `BitMatchTests/CopyVerifyExecutorIntegrityTests.swift`
- Modify: `Shared/Core/Services/ServiceProtocols.swift`
- Modify: `Shared/Core/Services/SharedFileOperationsService.swift`
- Modify: `Shared/Core/Services/CopyVerifyExecutor.swift`
- Modify: `BitMatchTests/SharedCompareFlowTests.swift`

**Interfaces:**
- Produces: `FileOperationsService.FileResultCallback = (FileOperationResult) async -> Void`.
- Changes: `performFileOperation(sourceURL:destinationURLs:verificationMode:settings:estimatedTotalBytes:progressCallback:onFileResult:)` so `onFileResult` accepts `FileResultCallback?`.
- Makes: `FileOperation.results` the only completion and report authority.
- Removes: unused executor `currentOperation` and `getCurrentResults()` state if repository-wide reference checks remain empty.

- [ ] **Step 1: Add a deterministic authoritative-results regression**

Create an `@MainActor` executor test with a fake file-operations service that returns a `FileOperation` containing one failed result but does not emit the optional presentation callback. Capture `onStateChange` and `onComplete`:

```swift
func testReturnedOperationFailureControlsCompletionWithoutPresentationCallback() async throws {
    let failure = FileOperationResult(
        sourceURL: URL(fileURLWithPath: "/source/clip.mov"),
        destinationURL: URL(fileURLWithPath: "/destination/clip.mov"),
        success: false,
        error: NSError(domain: "test", code: 1),
        fileSize: 10,
        verificationResult: nil,
        processingTime: 0
    )
    let harness = ExecutorHarness(returnedResults: [failure], emittedResults: [])

    _ = try await harness.execute()

    XCTAssertEqual(harness.completedRows.count, 1)
    XCTAssertFalse(harness.completedRows[0].isSuccessStatus)
    XCTAssertEqual(harness.terminalInfo?.success, false)
}
```

`ExecutorHarness` must build a real `CopyVerifyExecutor` with no-op timing, error, background, camera, and filesystem collaborators, plus a `FileOperationsService` fake that returns the supplied `FileOperation`.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-3 \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/CopyVerifyExecutorIntegrityTests
```

Expected: completion receives no rows and reports success because the executor reads the empty overflow store.

- [ ] **Step 3: Make result delivery asynchronous and ordered**

Define the callback alias and update the protocol:

```swift
protocol FileOperationsService {
    typealias ProgressCallback = (OperationProgress) -> Void
    typealias FileResultCallback = (FileOperationResult) async -> Void

    func performFileOperation(
        sourceURL: URL,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        settings: CameraLabelSettings,
        estimatedTotalBytes: Int64?,
        progressCallback: @escaping ProgressCallback,
        onFileResult: FileResultCallback?
    ) async throws -> FileOperation
}
```

Change every result emission in `SharedFileOperationsService` to `await onFileResult?(result)`. Update test doubles to the same callback type.

In `CopyVerifyExecutor`, call `await handleFileResult(fileResult, overflowService: overflowService, callbacks: callbacks)` directly from the asynchronous callback. Do not create a nested `Task`.

- [ ] **Step 4: Derive completion from `FileOperation.results`**

Map the final operation results directly:

```swift
let allResults = operation.results.map { fileResult in
    ResultRow(
        path: fileResult.sourceURL.path,
        status: fileResult.statusDescription,
        size: fileResult.fileSize,
        checksum: fileResult.verificationResult?.sourceChecksum,
        destination: driveName(for: fileResult.destinationURL),
        destinationPath: fileResult.destinationURL.path
    )
}
```

Use `allResults` for issue count, report input, and `onComplete`. In `SharedAppCoordinator`, assign `self.results = allResults` inside `onComplete`. Keep overflow storage operation-local and clear that exact actor on every exit. It may support live presentation, but it cannot decide success.

- [ ] **Step 5: Run executor, overflow, and transfer tests**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-3-green \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/CopyVerifyExecutorIntegrityTests \
  -only-testing:BitMatchTests/ResultsOverflowUpsertTests \
  -only-testing:BitMatchTests/SharedFileOperationsServiceTests \
  -only-testing:BitMatchTests/SharedFileOperationsParanoidTests
```

Expected: all tests pass and no completion callback can precede its result callback.

- [ ] **Step 6: Commit**

```bash
git add BitMatchTests/CopyVerifyExecutorIntegrityTests.swift \
  BitMatchTests/SharedCompareFlowTests.swift \
  Shared/Core/Services/ServiceProtocols.swift \
  Shared/Core/Services/SharedFileOperationsService.swift \
  Shared/Core/Services/CopyVerifyExecutor.swift
git commit -m "fix: make operation results authoritative"
```

---

### Task 4: Own cancellation and reject overlapping operations

**Files:**
- Create: `BitMatchTests/OperationOwnershipTests.swift`
- Modify: `Shared/Core/Services/File/SafetyValidator.swift`
- Modify: `Shared/Core/Services/SharedFileOperationsService.swift`
- Modify: `Shared/Core/Services/SharedAppCoordinator.swift`
- Modify: `Shared/Core/Services/CopyVerifyExecutor.swift`

**Interfaces:**
- Produces: `FileOperationError.operationAlreadyInProgress`.
- Produces: a private lock-protected active-operation registry in `SharedFileOperationsService` with reserve, attach, cancel, and clear operations keyed by UUID.
- Preserves: the synchronous public cancel entry point while ensuring Start stays disabled until the cancelled task unwinds.

- [ ] **Step 1: Add overlap and verifier-lifetime regressions**

Create a one-file real transfer fixture and a `BlockingChecksumService`. The service must signal when verification begins and wait on an actor-backed gate before returning. Add these tests:

```swift
func testSecondOperationIsRejectedWhileFirstIsActive() async throws
func testCancellationWaitsForVerifierCleanupBeforeOperationReturns() async throws
func testCoordinatorDoesNotEnableRestartUntilCancellationUnwinds() async throws
```

The first test starts operation A, waits until its checksum is blocked, then starts B on the same `SharedFileOperationsService`. Assert B throws `FileOperationError.operationAlreadyInProgress` and A remains active.

The second test cancels A, awaits A's result, releases the checksum gate, and asserts no result callback occurs after A returned.

The coordinator test uses a blocking `FileOperationsService` fake. After `cancelOperation()`, immediately call `startOperation()` again and assert the fake's start count remains one until the first task has unwound.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-4 \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/OperationOwnershipTests
```

Expected: B replaces or cancels A, verifier callbacks can escape cancellation, or the coordinator starts twice.

- [ ] **Step 3: Add the overlapping-operation error**

Add the enum case and message:

```swift
case operationAlreadyInProgress

case .operationAlreadyInProgress:
    return "Another file operation is already active or cancelling."
```

- [ ] **Step 4: Gate service ownership**

Replace implicit cancellation at the start of `performFileOperation` with an operation reservation. The private registry must:

- reserve an operation ID before its task begins;
- reject a second reservation;
- retain the task handle for cancellation;
- remember cancellation requested between reservation and attachment;
- clear only when the matching operation finishes;
- keep the active slot occupied until cleanup has completed.

Do not set the registry to idle inside `cancelOperation`; cancellation requests the task to stop, and the operation's exit path clears ownership.

- [ ] **Step 5: Cancel and await every verifier on every exit**

Add one helper around `VerifyTaskStore`:

```swift
private func finishVerificationTasks(
    in store: VerifyTaskStore,
    cancelling: Bool
) async {
    let tasks = await store.drain()
    if cancelling {
        tasks.forEach { $0.cancel() }
    }
    for task in tasks {
        await task.value
    }
}
```

Wrap the destination/copy/verify body in `do/catch`. On success, await all tasks. On error or cancellation, cancel and await them before throwing. Security scopes and the checksum pause hook must remain active until this cleanup finishes.

- [ ] **Step 6: Latch coordinator start before preflight**

Add `activeStartID: UUID?` and `startCancellationRequested`. After validating that selections exist, create the operation ID, assign it to `activeStartID`, clear the cancellation flag, and set `isOperationInProgress = true` before acquiring scopes or awaiting safety checks. Use that ID in `CopyVerifyConfig`. Use one token-matched `defer` to clear the ID, flag, and active latch after execution or cancellation has fully returned. `cancelOperation()` sets `startCancellationRequested = true` and signals the executor; it does not clear the active latch. Remove early `false` assignments from cancellation and callbacks that can expose Start while work still unwinds.

Callbacks must verify their operation ID before mutating shared state if any asynchronous publication remains.

- [ ] **Step 7: Run ownership and fault tests**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-4-green \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/OperationOwnershipTests \
  -only-testing:BitMatchTests/TransferFaultIntegrationTests \
  -only-testing:BitMatchTests/SharedFileOperationsServiceTests
```

Expected: all tests pass; the second operation is rejected without disturbing the first.

- [ ] **Step 8: Commit**

```bash
git add BitMatchTests/OperationOwnershipTests.swift \
  Shared/Core/Services/File/SafetyValidator.swift \
  Shared/Core/Services/SharedFileOperationsService.swift \
  Shared/Core/Services/SharedAppCoordinator.swift \
  Shared/Core/Services/CopyVerifyExecutor.swift
git commit -m "fix: scope cancellation to one active operation"
```

---

### Task 5: Derive completion and report status from all results

**Files:**
- Create: `Shared/Core/Models/ResultPresentation.swift`
- Create: `BitMatchTests/ResultPresentationTests.swift`
- Modify: `BitMatch-iPad/Views/CompletionSummaryView.swift`
- Modify: `BitMatch/Views/ReportView.swift`
- Modify: `BitMatch/Views/ResultsTableView.swift`

**Interfaces:**
- Produces: `ResultIntegritySummary.init(rows:)`, `successfulRows`, `issueRows`, `isSuccessful`.
- Produces: `CompletionVerdict.resolve(state:rows:hasErrors:hasCriticalErrors:)` with `.success`, `.issues`, and `.failed`.
- Produces: `ResultPresentation.visibleRows(_:issuesOnly:limit:)`.

- [ ] **Step 1: Add failing shared presentation tests**

Create tests for a successful media row plus a failed XML sidecar, a completed-false iPad outcome without diagnostic errors, and 1,001 failures:

```swift
func testSidecarFailureMakesIntegritySummaryFail() {
    let rows = [
        row("clip.mov", status: "✅ Verified"),
        row("clip.xml", status: "⚠️ Checksum Mismatch")
    ]
    let summary = ResultIntegritySummary(rows: rows)
    XCTAssertEqual(summary.issueRows.map(\.fileName), ["clip.xml"])
    XCTAssertFalse(summary.isSuccessful)
}

func testCompletedFalseResolvesToIssuesWithoutDiagnosticError() {
    let verdict = CompletionVerdict.resolve(
        state: .completed(OperationCompletionInfo(success: false, message: "1 issue")),
        rows: [row("clip.xml", status: "⚠️ Checksum Mismatch")],
        hasErrors: false,
        hasCriticalErrors: false
    )
    XCTAssertEqual(verdict, .issues)
}

func testVisibleRowsCapsMoreThanOneThousandIssuesWithoutTrapping() {
    let rows = (0..<1_001).map { row("\($0).mov", status: "❌ Failed") }
    XCTAssertEqual(ResultPresentation.visibleRows(rows, issuesOnly: false, limit: 1_000).count, 1_000)
}
```

Add these cases in the same file:

- `testUnknownStatusIsAnIntegrityIssue`: `"Unknown"` appears in `issueRows`.
- `testFailedRowOverridesCompletedTrueState`: a failed row resolves to `.issues` even when completion says true.
- `testCriticalDiagnosticResolvesToFailed`: a critical diagnostic resolves to `.failed`.
- `testCleanCompletedTrueResolvesToSuccess`: completed-true plus only successful rows resolves to `.success`.
- `testVisibleRowsFillsRemainingCapacityWithNewestSuccesses`: after issues, the helper selects the newest successful rows up to the limit.
- `testVisibleRowsHonorsZeroAndNegativeLimits`: both limits return an empty array.
- `testIssuesOnlyFiltersSuccessesBeforeApplyingLimit`: successful rows never appear when `issuesOnly` is true.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-5 \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/ResultPresentationTests
```

Expected: compilation fails because the shared presentation types do not exist.

- [ ] **Step 3: Implement the pure shared models**

Implement the result summary with `ResultRow.isSuccessStatus` only:

```swift
struct ResultIntegritySummary {
    let successfulRows: [ResultRow]
    let issueRows: [ResultRow]

    init(rows: [ResultRow]) {
        successfulRows = rows.filter(\.isSuccessStatus)
        issueRows = rows.filter { !$0.isSuccessStatus }
    }

    var isSuccessful: Bool { issueRows.isEmpty }
}
```

`CompletionVerdict.resolve` returns `.failed` for `.failed` or critical diagnostics, `.issues` for completed-false, failed rows, or noncritical diagnostics, and `.success` only for completed-true with no issues.

`ResultPresentation.visibleRows` selects issues with `prefix(limit)`, then fills remaining capacity with the newest successful rows. It must return at most `max(0, limit)` rows for every input.

- [ ] **Step 4: Wire truthful iPad completion**

In `CompletionStatusHeaderView`, resolve one `CompletionVerdict` from `coordinator.operationState`, `coordinator.results`, `coordinator.hasErrors`, and `coordinator.hasCriticalErrors`. Map that verdict to the existing icon, title, and colors. Do not infer success from diagnostics alone.

Show the issues section when the verdict is not `.success`, even if `errorService` has no entries. `ErrorDetailsView` must include `ResultIntegritySummary(rows: coordinator.results).issueRows.count` and tell the operator to review failed files before clearing source media.

- [ ] **Step 5: Wire truthful PDF and safe result limiting**

In `ReportView`, keep `relevantRows` only for the media manifest preview. Calculate verified count, issue count, issue details, issue summary, and success badge from `ResultIntegritySummary(rows: rows)`. Replace all status substring checks in the touched paths.

In `ResultsTableView`, derive `issueCount` and `filteredResults` from `ResultIntegritySummary` and `ResultPresentation.visibleRows`.

- [ ] **Step 6: Run presentation and report tests**

Run:

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data/integrity-task-5-green \
  CODE_SIGNING_ALLOWED=NO test \
  -only-testing:BitMatchTests/ResultPresentationTests \
  -only-testing:BitMatchTests/ResultStatusClassificationTests
```

Expected: all tests pass, and mixed media/sidecar results cannot produce a success verdict.

- [ ] **Step 7: Build the iPad target**

Run:

```bash
bash test.sh ipad-build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Shared/Core/Models/ResultPresentation.swift \
  BitMatchTests/ResultPresentationTests.swift \
  BitMatch-iPad/Views/CompletionSummaryView.swift \
  BitMatch/Views/ReportView.swift \
  BitMatch/Views/ResultsTableView.swift
git commit -m "fix: derive completion status from every result"
```

---

### Task 6: Run the full integrity verification gate

**Files:**
- Modify only if verification exposes a regression in code changed by Tasks 1-5.

**Interfaces:**
- Consumes all outputs from Tasks 1-5.
- Produces final build, test, soak, concurrency, cleanliness, and review evidence.

- [ ] **Step 1: Run the complete macOS suite**

```bash
bash test.sh mac-test
```

Expected: exit 0.

- [ ] **Step 2: Run iPad tests on the available simulator**

```bash
IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,id=7D66956B-38AD-48FB-B960-82D13BB1FE17' bash test.sh ipad-test
```

If that simulator ID no longer exists, select an installed iPad simulator with `xcrun simctl list devices available` and record the destination used.

- [ ] **Step 3: Run both Release builds**

```bash
bash test.sh release-builds
```

Expected: both builds succeed.

- [ ] **Step 4: Run strict-concurrency diagnostic builds**

```bash
xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .derived-data/strict-mac CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete build

xcodebuild -quiet -project BitMatch.xcodeproj -scheme BitMatch-iPad \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derived-data/strict-ipad CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete build
```

Expected: both builds succeed and touched code introduces no new warnings.

- [ ] **Step 5: Run the seeded soak**

```bash
BITMATCH_SOAK_ITERATIONS=3 bash Scripts/run_soak_tests.sh
```

Expected: three completed iterations and 18 verified outputs per iteration.

- [ ] **Step 6: Check the diff and repository state**

```bash
git diff --check
git status --short
```

Expected: only intentional source, test, spec, plan, and ledger changes remain.

- [ ] **Step 7: Request whole-branch review and fix every Critical or Important finding**

Generate the subagent-driven-development review package from the branch merge base. Give the reviewer the approved design, this plan, task reports, test evidence, and full diff. Re-run covering tests after any review fix.

- [ ] **Step 8: Remove generated artifacts**

```bash
rm -rf .derived-data
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'bitmatch-soak.*' -print
git status --short
```

Expected: no soak directories, no DerivedData, and a clean intentional diff.
