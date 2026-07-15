# SFTP Off-Site Backup Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Queue a locally verified photographer package to one saved SFTP destination and state exactly whether it is locally safe, uploaded unverified, or fully backed up.

**Architecture:** Preserve the local engine as authoritative. A locally-safe card creates an immutable checksum manifest and security-scoped bookmark to one verified local package. A persisted queue reads only that artifact through a provider-neutral interface; Citadel implements SFTP and fake providers prove queue behavior.

**Tech Stack:** Swift 6, SwiftUI, Core Data, Keychain, Citadel 0.12.x, `SharedChecksumService`.

## Global Constraints

- macOS SFTP only; no plain FTP, WebDAV, S3, iPad uploads, or proxy delivery.
- Citadel must use strict pinned host-key validation, never `.acceptAnything()`.
- Keep the Citadel adapter behind `#if os(macOS)` and make the shared provider factory return a typed unavailable error on iPad; the iPad build must not link Citadel.
- Core Data may store profiles, manifests, queue state, and opaque Keychain references only—never a credential, private key, passphrase, bookmark bytes, or auth header.
- Multiple saved profiles are allowed; one active remote target per job/card is allowed.
- Queue only `.locallySafe` cards. Resolve and validate the local bookmark, containment, byte count, and checksum before every upload. Never read the camera card.
- Reject absolute paths, empty components, `.`, `..`, separators in a component, and portable-name collisions.
- Never replace a final remote object. Use same-parent temporary paths and provider no-replace promotion; fail closed when unavailable.
- Verified state requires server SHA-256 or full read-back SHA-256. Upload-only is `Uploaded · Unverified`.
- The user forbids app launches, simulators, test execution, and test binaries locally. Add tests; run only compile-only `bash test.sh mac-build` and `bash test.sh ipad-build` here.

## Task 1: Model remote state, paths, manifests, and presentation

**Files:** Create `Shared/Core/Models/RemoteBackupModels.swift`, `BitMatchTests/RemoteBackupModelsTests.swift`; modify `Shared/Core/Models/PhotographerJobModels.swift`, `Shared/Core/Models/PhotographerJobPresentation.swift`, `BitMatchTests/PhotographerJobPresentationTests.swift`.

**Interfaces produced:**

```swift
enum RemoteBackupState: String, Codable, Sendable { case queued, uploading, retrying, paused, uploadedUnverified, verifying, verified, failed, cancelled, conflict }
enum RemoteVerificationEvidence: Codable, Equatable, Sendable { case sha256(String), readBackSHA256(String), none }
struct RemoteDestinationProfile: Identifiable, Codable, Equatable, Sendable { let id: UUID; var name: String; var host: String; var port: Int; var username: String; var root: RemoteRelativePath; var verificationMode: RemoteVerificationMode }
struct RemoteManifestEntry: Identifiable, Codable, Equatable, Sendable { let id: UUID; let relativePath: RemoteRelativePath; let byteCount: Int64; let sha256: String }
```

- [ ] Write tests proving `RemoteRelativePath(components: ["Job", "..", "Card-001"])` throws `RemotePathError.unsafeComponent("..")`, and only `.verified(.sha256("…"))` receives `Fully Backed Up` presentation.
- [ ] Add `RemoteBackupConfiguration`, `RemoteManifest`, `RemoteQueueItem`, target-ID-keyed card summaries, and explicit non-green states for queued/uploading/unverified/paused/conflict/failed.
- [ ] Compile-only validate with `bash test.sh mac-build`; commit `feat: model remote backup state`.

## Task 2: Persist profiles, queue items, and Keychain-only secrets

**Files:** Modify `BitMatch/BitMatch.xcdatamodeld/BitMatch.xcdatamodel/contents`, `BitMatch/Core/Services/Photographer/PhotographerJobStore.swift`, `BitMatch/Core/Services/Photographer/BitMatchPersistenceController.swift`, `BitMatch/Utilities/KeychainHelper.swift`; test `BitMatchTests/PhotographerJobStoreTests.swift`.

**Interfaces produced:**

```swift
func profiles() throws -> [RemoteDestinationProfile]
func save(_ profile: RemoteDestinationProfile) throws
func deleteProfile(id: UUID) throws
func queueItems() throws -> [RemoteQueueItem]
func save(_ item: RemoteQueueItem) throws
func deleteQueueItem(id: UUID) throws
```

- [ ] Add failing tests for profile round-trip without a password in encoded payload, deleting one profile deleting only its `remote-profile.<UUID>` Keychain entry, and unavailable Core Data retrying through the existing readiness callback.
- [ ] Add migration-safe `RemoteDestinationProfileRecord`, `RemoteManifestRecord`, and `RemoteQueueItemRecord` entities (UUID, timestamp, Codable payload); use the existing corrupt-record fail-closed decoding pattern.
- [ ] Add a typed `RemoteCredentialStore` over `KeychainHelper`; Core Data stores only its opaque account name.
- [ ] Compile-only validate with `bash test.sh mac-build`; commit `feat: persist remote backup profiles and queue`.

## Task 3: Provider boundary and actor-backed persistent queue

**Files:** Create `Shared/Core/Services/RemoteBackupProvider.swift`, `Shared/Core/Services/RemoteBackupQueue.swift`, `BitMatchTests/RemoteBackupQueueTests.swift`, and `BitMatchTests/SFTPRemoteBackupProviderContractTests.swift`.

**Interfaces produced:**

```swift
protocol RemoteBackupProvider: Sendable {
    func preflight(profile: RemoteDestinationProfile, credential: RemoteCredential) async throws -> RemoteProviderCapabilities
    func inspect(path: RemoteRelativePath) async throws -> RemoteObject?
    func ensureDirectory(_ path: RemoteRelativePath) async throws
    func upload(local: URL, toTemporary path: RemoteRelativePath, fromOffset: Int64, progress: @Sendable (Int64) async -> Void) async throws
    func promoteNoReplace(temporary: RemoteRelativePath, final: RemoteRelativePath) async throws
    func verificationEvidence(for path: RemoteRelativePath, expectedSHA256: String) async throws -> RemoteVerificationEvidence
    func close() async
}
actor RemoteBackupQueue { func restore(); func enqueue(_ item: RemoteQueueItem); func run(_ id: UUID) async; func cancel(_ id: UUID) }
```

- [ ] Write fake-provider tests that an existing conflicting final object produces `.conflict` and no upload call; an interrupted temporary upload resumes only when stored and server offsets agree; a network error persists retry/backoff; auth, host-key, path, bookmark, and permission failures pause/fail closed.
- [ ] Persist every material transition. Use capped exponential backoff plus jitter only for transient network faults. Require no-replace promotion and evidence capabilities when verified mode is selected.
- [ ] Compile-only validate with `bash test.sh mac-build`; commit `feat: add persistent remote backup queue`.

## Task 4: Build trusted remote manifests only from verified local results

**Files:** Create `Shared/Core/Services/RemoteBackupCoordinator.swift`, `BitMatchTests/RemoteBackupCoordinatorTests.swift`; modify `BitMatch/Core/ViewModels/PhotographerJobViewModel.swift`, `BitMatch/App/AppCoordinator.swift`, `BitMatchTests/PhotographerJobViewModelTests.swift`.

**Interfaces produced:** `selectRemoteProfile(_:)`, `queueRemoteBackup(for:)`, `pauseRemoteBackup(for:)`, `retryRemoteBackup(for:)`.

- [ ] Write tests that a copying/failed card throws `RemoteBackupError.localArtifactNotVerified`, and an item bookmark is never the source-card bookmark.
- [ ] Select artifact roots exclusively from authoritative final `ResultRow.destinationPath` values. Build manifest entries from confirmed checksum evidence, persist a security-scoped package bookmark, and re-check bookmark containment, file size, and SHA-256 before upload.
- [ ] Ensure remote errors never invoke `operationFailed()` or alter local evidence.
- [ ] Compile-only validate with `bash test.sh mac-build`; commit `feat: queue verified card packages for remote backup`.

## Task 5: Add the secure Citadel SFTP provider

**Files:** Modify `BitMatch.xcodeproj/project.pbxproj`, `BitMatch/Utilities/KeychainHelper.swift`; create `BitMatch/Core/Services/SFTPRemoteBackupProvider.swift`; modify `BitMatchTests/SFTPRemoteBackupProviderContractTests.swift`.

- [ ] Add contract tests that host-key fingerprint change blocks before authentication, a preexisting final causes `RemoteBackupError.conflict`, a temporary object resumes only at the confirmed server length, and a corrupt read-back fails verification.
- [ ] Add Citadel 0.12.x to the macOS target. First use requires a deliberate UI fingerprint confirmation; later connections compare fingerprint before credentials are sent. Keep the adapter inside `#if os(macOS)` and make the shared factory return `RemoteBackupError.providerUnavailable` on iPad.
- [ ] Resolve the configured root, create contained directories, inspect final/temporary paths, and always close the SFTP client. Use `.bitmatch-upload-<queue-item-uuid>` same-parent temporary names. Prefer an explicit server SHA-256 extension; otherwise read the final object through `SharedChecksumService`.
- [ ] Use provider no-replace promotion where the server exposes it. Otherwise recheck immediately before rename and classify any race as conflict, never verified success.
- [ ] Compile-only validate with `bash test.sh mac-build`; commit `feat: add secure SFTP remote backup provider`.

## Task 6: Add the compact off-site stage, dashboard, and reports

**Files:** Create `BitMatch/Views/Photographer/RemoteBackupDestinationView.swift`; modify `BitMatch/Views/Photographer/PhotographerJobSetupView.swift`, `BitMatch/Views/Photographer/PhotographerSessionDashboard.swift`, `BitMatch/Core/Services/ReportExporter.swift`, `BitMatch/Views/ReportView.swift`; test `BitMatchTests/PhotographerJobPresentationTests.swift` and `BitMatchTests/PhotographerReportTests.swift`.

- [ ] Write presentation tests that disabled off-site backup remains a single compact row and `Uploaded · Unverified` is warning-colored, plus report tests that local `Locally Safe` remains true while `fullyBackedUpAt` is nil for unverified uploads and no secret reaches JSON/CSV/PDF.
- [ ] Reveal profile picker, manage/test actions, remote folder policy, rendered remote path, verification choice, and read-back data-cost warning only after enabling the optional off-site row. Disable queue controls until both local safety and a saved credential exist.
- [ ] Present local and remote verdicts separately in the dashboard/reports, including target, provider, remote path, attempts, evidence, warning, conflict, and failure details. Only a SHA-256/read-back match may say `Fully Backed Up`.
- [ ] Compile-only validate with `bash test.sh mac-build && bash test.sh ipad-build`; conduct a read-only review for credential leakage, host-key handling, path escape, artifact substitution, resume, overwrite conflicts, and normal local-copy regressions. Remove generated build/review scratch; commit `feat: present and report off-site backup evidence`.

## Plan Self-Review

- Coverage includes profiles/Keychain, one active SFTP target, persistent queueing, trusted local artifacts, interrupted uploads, no-overwrite promotion, verification, honest UI/reports, and regression boundaries.
- WebDAV/S3, iPad scheduling, and the future cross-media proxy/delivery system are explicitly excluded.
- Every consumer uses a type introduced by an earlier task; no credential-bearing type crosses into persistence or reports.
