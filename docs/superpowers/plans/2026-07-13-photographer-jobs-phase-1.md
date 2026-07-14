# Photographer Jobs Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add wedding and event jobs, configurable folder recipes, card provenance, duplicate warnings, photographer-aware reports, and a local-only session dashboard without changing BitMatch's verified-copy guarantees.

**Architecture:** New shared value types describe jobs, card ingests, folder recipes, and analysis. A small macOS Core Data repository persists encoded jobs and presets. The existing local transfer engine remains authoritative; an optional list of safe destination subdirectory components lets it write exact card contents beneath a rendered job package.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, Core Data, CryptoKit, XCTest, Swift Testing, Xcode 16.4+, macOS 15.5+, iPadOS 18.5+ build compatibility.

## Global Constraints

- Preserve exact card contents. Do not rename, flatten, convert, or rearrange files inside a card package.
- Preserve existing local copy, temp-write, no-overwrite, source-stability, and verification behavior.
- Require at least one verified local destination; the Wedding preset defaults to two.
- Treat RAW/JPEG/sidecar grouping as report metadata, not a transfer filter or failure policy.
- Store no remote-provider code or credentials in this phase.
- Keep all new shared models `Codable`, `Equatable`, and `Sendable` where their members permit it.
- Use TDD for every behavior change. Observe the intended failing test before implementation.
- Run macOS tests and iPad builds after shared-code changes.
- Put every build's DerivedData under `.derived-data/photographer-phase-1/`; remove it after each task and before final handoff.
- Execute in a Superpowers-owned `.worktrees/` worktree. Remove that worktree after integration.

---

## File map

### Shared domain and analysis

- Create `Shared/Core/Models/PhotographerJobModels.swift` — job, ingest, preset, recipe, status, provenance, and report-context value types.
- Create `Shared/Core/Services/FolderRecipeRenderer.swift` — safe layer rendering and path preview.
- Create `Shared/Core/Services/PhotographerCardAnalyzer.swift` — preliminary/confirmed fingerprints and companion grouping.
- Modify `Shared/Core/Services/File/FileTreeEnumerator.swift` — include modification dates required by the preliminary fingerprint.
- Modify `Shared/Core/Models/CameraModels.swift` — carry optional safe destination path components for one operation.
- Modify `Shared/Core/Services/File/SafetyValidator.swift` — resolve and validate recipe-based destination roots.

### Persistence and coordination

- Modify `BitMatch/BitMatch.xcdatamodeld/BitMatch.xcdatamodel/contents` — add encoded job and preset records.
- Create `BitMatch/Core/Services/Photographer/BitMatchPersistenceController.swift` — macOS persistent container.
- Create `BitMatch/Core/Services/Photographer/PhotographerJobStore.swift` — repository protocol and Core Data implementation.
- Create `BitMatch/Core/ViewModels/PhotographerJobViewModel.swift` — setup state, preview, ingest lifecycle, duplicate warning, and session rows.
- Modify `BitMatch/App/AppCoordinator.swift` — bind the active job to local transfer setup and completion.

### Presentation and reporting

- Create `Shared/Core/Models/PhotographerJobPresentation.swift` — pure view-ready setup and session summaries.
- Create `BitMatch/Views/Photographer/PhotographerJobSetupView.swift` — job fields, preset, and Customize layers disclosure.
- Create `BitMatch/Views/Photographer/PhotographerSessionDashboard.swift` — card-level local states and provenance.
- Modify `BitMatch/Views/CopyAndVerify/TransferPlanView.swift` — insert compact photographer setup and rendered destination preview.
- Modify `Shared/Core/Services/CopyVerifyExecutor.swift` — pass optional photographer report context.
- Modify `BitMatch/Core/Services/ReportExporter.swift` — add job, photographer, camera, card, grouping, and duplicate information to JSON and PDF summaries.

### Tests

- Create `BitMatchTests/FolderRecipeRendererTests.swift`.
- Create `BitMatchTests/PhotographerCardAnalyzerTests.swift`.
- Create `BitMatchTests/PhotographerJobStoreTests.swift`.
- Create `BitMatchTests/PhotographerDestinationLayoutTests.swift`.
- Create `BitMatchTests/PhotographerJobViewModelTests.swift`.
- Create `BitMatchTests/PhotographerJobPresentationTests.swift`.
- Create `BitMatchTests/PhotographerReportTests.swift`.

---

### Task 1: Job domain and folder recipes

**Files:**
- Create: `Shared/Core/Models/PhotographerJobModels.swift`
- Create: `Shared/Core/Services/FolderRecipeRenderer.swift`
- Test: `BitMatchTests/FolderRecipeRendererTests.swift`

**Interfaces:**
- Produces: `FolderLayer`, `FolderRecipe`, `FolderRecipeContext`, `FolderRecipeRenderer.render(_:context:) throws -> RenderedFolderRecipe`.
- Consumed by: Tasks 3–7.

- [ ] **Step 1: Write the failing folder-recipe tests**

```swift
import Testing
@testable import BitMatch

struct FolderRecipeRendererTests {
    private let context = FolderRecipeContext(
        eventDate: Date(timeIntervalSince1970: 1_783_915_200),
        jobName: "Smith Wedding",
        photographer: "Mike",
        camera: "Sony A7 IV",
        cardNumber: 1
    )

    @Test func weddingPresetRendersExpectedComponents() throws {
        let rendered = try FolderRecipeRenderer.render(.wedding, context: context)
        #expect(rendered.components == [
            "2026-07-13_Smith-Wedding", "Originals", "Mike", "Sony-A7-IV", "Card-001"
        ])
    }

    @Test func disabledLayerIsOmittedWithoutChangingCardContents() throws {
        var recipe = FolderRecipe.wedding
        recipe.layers[2].isEnabled = false
        let rendered = try FolderRecipeRenderer.render(recipe, context: context)
        #expect(!rendered.components.contains("Mike"))
        #expect(rendered.components.last == "Card-001")
    }

    @Test func emptyJobNameFailsClosed() {
        let invalid = FolderRecipeContext(
            eventDate: context.eventDate,
            jobName: "  ",
            photographer: "Mike",
            camera: "Sony A7 IV",
            cardNumber: 1
        )
        #expect(throws: FolderRecipeError.self) {
            try FolderRecipeRenderer.render(.wedding, context: invalid)
        }
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild -project BitMatch.xcodeproj \
  -derivedDataPath .derived-data/photographer-phase-1/task-1 \
  CODE_SIGNING_ALLOWED=NO test -scheme BitMatch -destination 'platform=macOS' \
  -only-testing:BitMatchTests/FolderRecipeRendererTests
```

Expected: compilation fails because `FolderRecipeContext` and `FolderRecipeRenderer` do not exist.

- [ ] **Step 3: Add the shared domain types**

Implement these exact public shapes in `PhotographerJobModels.swift`:

```swift
import Foundation

enum PhotographerEventType: String, Codable, CaseIterable, Sendable {
    case wedding = "Wedding"
    case event = "Event"
    case portrait = "Portrait"
    case commercial = "Commercial"
}

enum FolderLayerKind: String, Codable, CaseIterable, Sendable {
    case dateAndJob
    case originals
    case photographer
    case camera
    case cardNumber
}

struct FolderLayer: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: FolderLayerKind
    var isEnabled: Bool
}

struct FolderRecipe: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var layers: [FolderLayer]

    static let wedding = FolderRecipe(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Wedding",
        layers: FolderLayerKind.allCases.map {
            FolderLayer(id: UUID(), kind: $0, isEnabled: true)
        }
    )
}

struct FolderRecipeContext: Equatable, Sendable {
    let eventDate: Date
    let jobName: String
    let photographer: String
    let camera: String
    let cardNumber: Int
}

struct RenderedFolderRecipe: Equatable, Sendable {
    let components: [String]
    var relativePath: String { components.joined(separator: "/") }
}

enum FolderRecipeError: LocalizedError, Equatable {
    case missingRequiredValue(String)
    case invalidCardNumber

    var errorDescription: String? {
        switch self {
        case .missingRequiredValue(let label): return "Enter a value for \(label)."
        case .invalidCardNumber: return "Card number must be greater than zero."
        }
    }
}

enum PhotographerLocalState: String, Codable, Sendable {
    case notStarted, copying, verifying, locallySafe, issues, cancelled
}

struct PhotographerIdentity: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
}

struct CardProvenance: Codable, Equatable, Sendable {
    var photographerID: UUID
    var photographerName: String
    var cameraName: String
    var cardNumber: Int
    var preliminaryFingerprint: String?
    var confirmedFingerprint: String?
}

struct CardIngest: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var provenance: CardProvenance
    var sourceDisplayName: String
    var renderedRelativePath: String
    var localState: PhotographerLocalState
    var startedAt: Date?
    var locallySafeAt: Date?
    var fileCount: Int
    var totalBytes: Int64
}

struct PhotographerJob: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var eventDate: Date
    var clientName: String
    var jobName: String
    var eventType: PhotographerEventType
    var photographers: [PhotographerIdentity]
    var recipe: FolderRecipe
    var requiredLocalCopyCount: Int
    var cardIngests: [CardIngest]
    var createdAt: Date
    var updatedAt: Date
}

struct PhotographerPreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var eventType: PhotographerEventType
    var recipe: FolderRecipe
    var requiredLocalCopyCount: Int
}
```

- [ ] **Step 4: Implement the renderer**

`FolderRecipeRenderer.render` must reject card numbers below one, require nonempty values for enabled dynamic layers, sanitize with `CameraLabelSettings.sanitizePathComponent`, replace spaces with dashes for camera names, and format card numbers as three digits. Portable source-path collision detection remains in the existing enumeration and safety-validation pipeline; repeated folder-layer values are not themselves a collision.

```swift
enum FolderRecipeRenderer {
    static func render(_ recipe: FolderRecipe, context: FolderRecipeContext) throws -> RenderedFolderRecipe {
        guard context.cardNumber > 0 else { throw FolderRecipeError.invalidCardNumber }
        var components: [String] = []
        for layer in recipe.layers where layer.isEnabled {
            let raw: String
            switch layer.kind {
            case .dateAndJob:
                raw = "\(dateFormatter.string(from: context.eventDate))_\(try required(context.jobName, "job name"))"
            case .originals: raw = "Originals"
            case .photographer: raw = try required(context.photographer, "photographer")
            case .camera: raw = try required(context.camera, "camera").replacingOccurrences(of: " ", with: "-")
            case .cardNumber: raw = String(format: "Card-%03d", context.cardNumber)
            }
            components.append(CameraLabelSettings.sanitizePathComponent(raw))
        }
        guard !components.isEmpty else { throw FolderRecipeError.missingRequiredValue("folder layers") }
        return RenderedFolderRecipe(components: components)
    }

    private static let dateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static func required(_ value: String, _ label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderRecipeError.missingRequiredValue(label) }
        return trimmed
    }
}
```

- [ ] **Step 5: Verify GREEN and clean DerivedData**

Run the Task 1 command again. Expected: all `FolderRecipeRendererTests` pass. Then run:

```bash
rm -rf .derived-data/photographer-phase-1/task-1
```

- [ ] **Step 6: Commit**

```bash
git add Shared/Core/Models/PhotographerJobModels.swift \
  Shared/Core/Services/FolderRecipeRenderer.swift \
  BitMatchTests/FolderRecipeRendererTests.swift
git commit -m "feat: add photographer job recipes"
```

---

### Task 2: Card fingerprints and companion analysis

**Files:**
- Modify: `Shared/Core/Services/File/FileTreeEnumerator.swift`
- Create: `Shared/Core/Services/PhotographerCardAnalyzer.swift`
- Test: `BitMatchTests/PhotographerCardAnalyzerTests.swift`

**Interfaces:**
- Consumes: `FileEntry` from `FileTreeEnumerator`.
- Produces: `CardAnalysis`, `PhotoCompanionGroup`, `PhotographerCardAnalyzer.preliminaryAnalysis(entries:)`, and `confirmedFingerprint(results:)`.
- Consumed by: Tasks 5 and 7.

- [ ] **Step 1: Write failing analysis tests**

```swift
import Foundation
import Testing
@testable import BitMatch

struct PhotographerCardAnalyzerTests {
    @Test func preliminaryFingerprintIgnoresEnumerationOrder() throws {
        let date = Date(timeIntervalSince1970: 100)
        let a = FileEntry(url: URL(fileURLWithPath: "/card/DCIM/A.ARW"), relativePath: "DCIM/A.ARW", size: 10, modificationDate: date)
        let b = FileEntry(url: URL(fileURLWithPath: "/card/DCIM/A.JPG"), relativePath: "DCIM/A.JPG", size: 5, modificationDate: date)
        #expect(try PhotographerCardAnalyzer.preliminaryAnalysis(entries: [a, b]).fingerprint ==
                PhotographerCardAnalyzer.preliminaryAnalysis(entries: [b, a]).fingerprint)
    }

    @Test func rawAndJpegWithSameStemFormOneGroup() throws {
        let entries = [
            FileEntry(url: URL(fileURLWithPath: "/c/A.ARW"), relativePath: "A.ARW", size: 10, modificationDate: nil),
            FileEntry(url: URL(fileURLWithPath: "/c/A.JPG"), relativePath: "A.JPG", size: 5, modificationDate: nil),
            FileEntry(url: URL(fileURLWithPath: "/c/A.XMP"), relativePath: "A.XMP", size: 1, modificationDate: nil)
        ]
        let analysis = try PhotographerCardAnalyzer.preliminaryAnalysis(entries: entries)
        let group = try #require(analysis.companionGroups.first)
        #expect(analysis.companionGroups.count == 1)
        #expect(group.rawPaths == ["A.ARW"])
        #expect(group.jpegPaths == ["A.JPG"])
        #expect(group.sidecarPaths == ["A.XMP"])
    }
}
```

- [ ] **Step 2: Run RED**

Run the focused xcodebuild command from Task 1 with `-only-testing:BitMatchTests/PhotographerCardAnalyzerTests` and DerivedData path `task-2`. Expected: compilation fails because the analyzer and the new `FileEntry` initializer do not exist.

- [ ] **Step 3: Extend `FileEntry` and enumeration**

Add `modificationDate: Date?`, an explicit initializer, and `.contentModificationDateKey` to the enumerator's keys. Populate the property from `URLResourceValues.contentModificationDate`.

```swift
struct FileEntry {
    let url: URL
    let relativePath: String
    let size: Int64
    let modificationDate: Date?

    init(url: URL, relativePath: String, size: Int64, modificationDate: Date? = nil) {
        self.url = url
        self.relativePath = relativePath
        self.size = size
        self.modificationDate = modificationDate
    }
}
```

- [ ] **Step 4: Implement deterministic analysis**

Create these exact `Codable`, `Equatable`, and `Sendable` value shapes:

```swift
struct PhotoCompanionGroup: Codable, Equatable, Sendable {
    let stem: String
    let rawPaths: [String]
    let jpegPaths: [String]
    let sidecarPaths: [String]
}

struct CardAnalysis: Codable, Equatable, Sendable {
    let fingerprint: String
    let fileCount: Int
    let totalBytes: Int64
    let companionGroups: [PhotoCompanionGroup]
}
```

Canonicalize entries by lowercased relative path. Hash UTF-8 lines containing relative path, size, and whole-second modification time with CryptoKit SHA-256. Group RAW extensions (`arw`, `cr2`, `cr3`, `nef`, `nrw`, `raf`, `orf`, `rw2`, `dng`), JPEG extensions (`jpg`, `jpeg`), and sidecars (`xmp`, `aae`, `dop`, `cos`).

Add:

```swift
enum PhotographerCardAnalyzer {
    static func preliminaryAnalysis(entries: [FileEntry]) throws -> CardAnalysis
    static func confirmedFingerprint(results: [ResultRow]) throws -> String
}
```

`confirmedFingerprint` must sort successful rows by source path and hash `path\0size\0checksum`; it must throw `CardAnalysisError.incompleteVerification` when a row failed or lacks a checksum.

- [ ] **Step 5: Verify GREEN, run existing enumerator tests, and clean**

Run focused analyzer tests and `FileTreeEnumeratorTests`. Expected: both suites pass. Remove `.derived-data/photographer-phase-1/task-2`.

- [ ] **Step 6: Commit**

```bash
git add Shared/Core/Services/File/FileTreeEnumerator.swift \
  Shared/Core/Services/PhotographerCardAnalyzer.swift \
  BitMatchTests/PhotographerCardAnalyzerTests.swift
git commit -m "feat: analyze photographer card provenance"
```

---

### Task 3: Core Data job and preset repository

**Files:**
- Modify: `BitMatch/BitMatch.xcdatamodeld/BitMatch.xcdatamodel/contents`
- Create: `BitMatch/Core/Services/Photographer/BitMatchPersistenceController.swift`
- Create: `BitMatch/Core/Services/Photographer/PhotographerJobStore.swift`
- Test: `BitMatchTests/PhotographerJobStoreTests.swift`

**Interfaces:**
- Consumes: `PhotographerJob`, `PhotographerPreset` from Task 1.
- Produces: `PhotographerJobStore` and `CoreDataPhotographerJobStore`.
- Consumed by: Task 5.

- [ ] **Step 1: Write failing in-memory repository tests**

Test save/fetch/delete for jobs, save/fetch for presets, update-by-ID, malformed payload reporting, and persistence of a Wedding preset requiring two local copies. Construct the store with an in-memory `NSPersistentContainer`.

```swift
@MainActor
@Test func savedJobRoundTrips() throws {
    let persistence = BitMatchPersistenceController(inMemory: true)
    let store = CoreDataPhotographerJobStore(context: persistence.container.viewContext)
    let now = Date(timeIntervalSince1970: 200)
    let job = PhotographerJob(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        eventDate: Date(timeIntervalSince1970: 100),
        clientName: "Smith",
        jobName: "Smith Wedding",
        eventType: .wedding,
        photographers: [],
        recipe: .wedding,
        requiredLocalCopyCount: 2,
        cardIngests: [],
        createdAt: now,
        updatedAt: now
    )
    try store.save(job)
    #expect(try store.jobs() == [job])
}
```

- [ ] **Step 2: Run RED**

Run `PhotographerJobStoreTests` with DerivedData path `task-3`. Expected: compilation fails because the persistence controller and store do not exist.

- [ ] **Step 3: Add Core Data records**

Add `PhotographerJobRecord` and `PhotographerPresetRecord` entities. Each entity has nonoptional `id: UUID`, nonoptional `updatedAt: Date`, and nonoptional `payload: Binary Data`. Set `codeGenerationType="class"` and the module to `Current Product Module`.

- [ ] **Step 4: Implement the persistence controller**

```swift
import CoreData

final class BitMatchPersistenceController {
    static let shared = BitMatchPersistenceController()
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "BitMatch")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Could not load BitMatch store: \(error.localizedDescription)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
```

- [ ] **Step 5: Implement the repository**

```swift
@MainActor
protocol PhotographerJobStore {
    func jobs() throws -> [PhotographerJob]
    func save(_ job: PhotographerJob) throws
    func deleteJob(id: UUID) throws
    func presets() throws -> [PhotographerPreset]
    func save(_ preset: PhotographerPreset) throws
}
```

`CoreDataPhotographerJobStore` must fetch by UUID, update or insert, encode payloads with ISO-8601 JSON dates, sort jobs by updated date descending, sort presets by name, and throw `PhotographerStoreError.corruptRecord(UUID)` on decode failure. Save the context only when it has changes.

- [ ] **Step 6: Verify GREEN and clean**

Run `PhotographerJobStoreTests`. Expected: all repository tests pass. Remove `.derived-data/photographer-phase-1/task-3`.

- [ ] **Step 7: Commit**

```bash
git add BitMatch/BitMatch.xcdatamodeld/BitMatch.xcdatamodel/contents \
  BitMatch/Core/Services/Photographer \
  BitMatchTests/PhotographerJobStoreTests.swift
git commit -m "feat: persist photographer jobs"
```

---

### Task 4: Safe job-package destination roots

**Files:**
- Modify: `Shared/Core/Models/CameraModels.swift`
- Modify: `Shared/Core/Services/File/SafetyValidator.swift`
- Create: `Shared/Core/Services/PhotographerDestinationResolver.swift`
- Test: `BitMatchTests/PhotographerDestinationLayoutTests.swift`
- Modify tests that initialize `CameraLabelSettings` only if compilation requires explicit new arguments.

**Interfaces:**
- Consumes: `RenderedFolderRecipe` from Task 1.
- Produces: `CameraLabelSettings.destinationPathComponents: [String]?` and `PhotographerDestinationResolver.operationSettings(base:components:)`.
- Consumed by: Tasks 5–7 and the existing copy engine.

- [ ] **Step 1: Write failing destination tests**

Cover exact nested root rendering, traversal rejection, empty-component rejection, legacy camera-label behavior when the optional components are nil, source/destination overlap, and conflicting existing files.

```swift
@Test func recipeComponentsReplaceLegacyCardFolder() throws {
    var settings = CameraLabelSettings()
    settings.destinationPathComponents = ["2026-07-13_Smith-Wedding", "Originals", "Mike", "Sony-A7-IV", "Card-001"]
    let root = SafetyValidator.resolvedDestinationRoot(
        source: URL(fileURLWithPath: "/Volumes/CARD"),
        destination: URL(fileURLWithPath: "/Volumes/SSD"),
        settings: settings
    )
    #expect(root.path == "/Volumes/SSD/2026-07-13_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001")
}
```

- [ ] **Step 2: Run RED**

Run `PhotographerDestinationLayoutTests` with DerivedData path `task-4`. Expected: compilation fails because `destinationPathComponents` does not exist.

- [ ] **Step 3: Add the optional operation layout**

Add this property with a nil default to `CameraLabelSettings`:

```swift
var destinationPathComponents: [String]? = nil
```

In `SafetyValidator.resolvedDestinationRoot`, use legacy behavior when the property is nil. When nonnil, require at least one component, sanitize every component, reject values that sanitize to `untitled` unless the original value equals `untitled`, and append each component separately. Add a throwing `resolvedDestinationRootChecked` helper and use it from `validateResolvedDestinationRoots`; keep the nonthrowing helper only for legacy callers and tests.

- [ ] **Step 4: Add the resolver**

```swift
enum PhotographerDestinationResolver {
    static func operationSettings(
        base: CameraLabelSettings,
        renderedRecipe: RenderedFolderRecipe
    ) -> CameraLabelSettings {
        var value = base
        value.destinationPathComponents = renderedRecipe.components
        return value
    }
}
```

- [ ] **Step 5: Verify GREEN and regression safety**

Run `PhotographerDestinationLayoutTests`, `SafetyValidatorTests`, and `SharedFileOperationsEdgeCaseTests`. Expected: all pass. Remove `.derived-data/photographer-phase-1/task-4`.

- [ ] **Step 6: Commit**

```bash
git add Shared/Core/Models/CameraModels.swift \
  Shared/Core/Services/File/SafetyValidator.swift \
  Shared/Core/Services/PhotographerDestinationResolver.swift \
  BitMatchTests/PhotographerDestinationLayoutTests.swift
git commit -m "feat: resolve photographer package destinations"
```

---

### Task 5: Job lifecycle and coordinator integration

**Files:**
- Create: `BitMatch/Core/ViewModels/PhotographerJobViewModel.swift`
- Modify: `BitMatch/App/AppCoordinator.swift`
- Test: `BitMatchTests/PhotographerJobViewModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `PhotographerJobViewModel.activeJob`, `activeCardDraft`, `renderedRecipe`, `duplicateWarning`, `beginIngest`, `completeIngest`, and `cancelIngest`.
- Consumed by: Tasks 6 and 7.

- [ ] **Step 1: Write failing lifecycle tests**

Use an in-memory `PhotographerJobStore` fake. Cover Wedding defaults, sequential card numbering per camera, rendered previews, preliminary duplicate warnings, `copying → verifying → locallySafe`, required copy count, failed-row issues, confirmed fingerprints, persistence after each transition, and reset for the next card.

```swift
@MainActor
@Test func completionRequiresConfiguredVerifiedDestinationCount() throws {
    let store = InMemoryPhotographerJobStore()
    let viewModel = PhotographerJobViewModel(store: store, now: { Date(timeIntervalSince1970: 200) })
    viewModel.createWeddingJob(
        clientName: "Smith",
        jobName: "Smith Wedding",
        eventDate: Date(timeIntervalSince1970: 100)
    )
    try viewModel.prepareCard(
        photographerName: "Mike",
        cameraName: "Sony A7 IV",
        analysis: CardAnalysis(
            fingerprint: "preliminary",
            fileCount: 1,
            totalBytes: 100,
            companionGroups: []
        )
    )
    viewModel.beginIngest(destinationCount: 2)
    try viewModel.completeIngest(results: [
        ResultRow(path: "/card/A.ARW", status: "✅ Verified", size: 100, checksum: "abc", destination: "Primary", destinationPath: "/primary/A.ARW"),
        ResultRow(path: "/card/A.ARW", status: "✅ Verified", size: 100, checksum: "abc", destination: "Secondary", destinationPath: "/secondary/A.ARW")
    ])
    #expect(viewModel.activeCard?.localState == .locallySafe)
}
```

- [ ] **Step 2: Run RED**

Run `PhotographerJobViewModelTests` with DerivedData path `task-5`. Expected: compilation fails because the view model does not exist.

- [ ] **Step 3: Implement the view model**

Make it `@MainActor final class PhotographerJobViewModel: ObservableObject`. Inject `any PhotographerJobStore`, a `now` closure, and analyzer functions. Published properties must include:

```swift
@Published private(set) var jobs: [PhotographerJob] = []
@Published var activeJob: PhotographerJob?
@Published var selectedPhotographerID: UUID?
@Published var cameraName = ""
@Published private(set) var renderedRecipe: RenderedFolderRecipe?
@Published private(set) var preliminaryAnalysis: CardAnalysis?
@Published private(set) var duplicateWarning: DuplicateCardWarning?
@Published private(set) var lastError: String?
```

`completeIngest` must derive destination success from authoritative `ResultRow` values grouped by destination path. It may set `locallySafe` only when the number of destinations with no failed or unverified rows reaches `requiredLocalCopyCount`. Persist after every state transition.

Define `DuplicateCardWarning` as an `Equatable, Sendable` value containing the prior `jobID`, prior `cardIngestID`, fingerprint, and human-readable message. Define the test-only `InMemoryPhotographerJobStore` in `PhotographerJobViewModelTests.swift`; it implements every repository requirement with arrays and records its save count so transition persistence can be asserted.

- [ ] **Step 4: Bind the coordinator**

Add `@Published var photographerJobViewModel` to `AppCoordinator`, constructed with the Core Data store. Before synchronizing settings in `startOperation`, copy camera settings through `PhotographerDestinationResolver` when a job/card is prepared. On progress stage changes, update the card state. On terminal completion, pass the full authoritative `sharedCoordinator.results` to `completeIngest`. On cancellation, call `cancelIngest`.

Do not change `SharedFileOperationsService` or read results from presentation callbacks before `onComplete` supplies the authoritative array.

- [ ] **Step 5: Verify GREEN and coordinator regressions**

Run `PhotographerJobViewModelTests`, `AppCoordinatorBindingTests`, `CopyVerifyExecutorIntegrityTests`, and `ResultPresentationTests`. Expected: all pass. Remove `.derived-data/photographer-phase-1/task-5`.

- [ ] **Step 6: Commit**

```bash
git add BitMatch/Core/ViewModels/PhotographerJobViewModel.swift \
  BitMatch/App/AppCoordinator.swift \
  BitMatchTests/PhotographerJobViewModelTests.swift
git commit -m "feat: track photographer ingest lifecycle"
```

---

### Task 6: Photographer setup and session dashboard

**Files:**
- Create: `Shared/Core/Models/PhotographerJobPresentation.swift`
- Create: `BitMatch/Views/Photographer/PhotographerJobSetupView.swift`
- Create: `BitMatch/Views/Photographer/PhotographerSessionDashboard.swift`
- Modify: `BitMatch/Views/CopyAndVerify/TransferPlanView.swift`
- Test: `BitMatchTests/PhotographerJobPresentationTests.swift`

**Interfaces:**
- Consumes: `PhotographerJobViewModel` from Task 5.
- Produces: compact setup disclosure, live folder preview, duplicate warning, and card-session rows.
- Consumed by: Task 7 final validation.

- [ ] **Step 1: Write failing pure presentation tests**

Cover collapsed summary text, disabled-layer preview, missing photographer/camera blockers, duplicate warning copy, status labels, required-copy counts, and card sorting.

```swift
@Test func locallySafeCardUsesExplicitStatusCopy() {
    let photographerID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    let card = CardIngest(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        provenance: CardProvenance(
            photographerID: photographerID,
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            cardNumber: 1,
            preliminaryFingerprint: "preliminary",
            confirmedFingerprint: "confirmed"
        ),
        sourceDisplayName: "CARD1",
        renderedRelativePath: "2026-07-13_Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-001",
        localState: .locallySafe,
        startedAt: Date(timeIntervalSince1970: 100),
        locallySafeAt: Date(timeIntervalSince1970: 200),
        fileCount: 1,
        totalBytes: 100
    )
    let row = PhotographerCardRowPresentation.make(card: card, verifiedDestinationCount: 2)
    #expect(row.statusTitle == "Locally Safe")
    #expect(row.statusSymbol == "checkmark.shield.fill")
}
```

- [ ] **Step 2: Run RED**

Run `PhotographerJobPresentationTests` with DerivedData path `task-6`. Expected: compilation fails because the presentation types do not exist.

- [ ] **Step 3: Implement pure presentation types**

Create `PhotographerJobSetupPresentation`, `PhotographerCardRowPresentation`, and `PhotographerSessionPresentation`. Keep all validation and copy outside SwiftUI views. Use these exact status labels: `Not Started`, `Copying`, `Verifying`, `Locally Safe`, `Issues`, and `Cancelled`.

- [ ] **Step 4: Build the setup disclosure**

`PhotographerJobSetupView` must show:

- Wedding preset selected by default;
- client/job name, date, photographer, camera, and card number;
- a live monospace folder preview;
- a collapsed **Customize layers** disclosure;
- toggles and move-up/move-down controls for layers;
- a **Save as preset** action;
- duplicate-card warning with a link to the earlier ingest row.

Use native controls, existing `DesignSystem` spacing/colors, and accessibility labels. Keep the disclosure collapsed after the first valid setup.

- [ ] **Step 5: Add the session dashboard and transfer-plan placement**

Place the compact job setup between the source/destination selection row and preflight. Show the dashboard below the active transfer when the job contains at least one ingest. Do not show empty dashboard chrome. Each row shows photographer, camera, card, file count, bytes, rendered path, local status, and verified destination count.

- [ ] **Step 6: Verify GREEN, build both platforms, and clean**

Run presentation tests, macOS tests, `bash test.sh mac-build`, and `bash test.sh ipad-build`. The iPad UI does not expose jobs yet, but shared files must compile. Use `DERIVED_DATA_ROOT="$PWD/.derived-data/photographer-phase-1/task-6"`. Expected: tests and both builds pass. Remove the task directory.

- [ ] **Step 7: Commit**

```bash
git add Shared/Core/Models/PhotographerJobPresentation.swift \
  BitMatch/Views/Photographer \
  BitMatch/Views/CopyAndVerify/TransferPlanView.swift \
  BitMatchTests/PhotographerJobPresentationTests.swift
git commit -m "feat: add photographer job workspace"
```

---

### Task 7: Photographer reports and end-to-end verification

**Files:**
- Modify: `Shared/Core/Models/PhotographerJobModels.swift`
- Modify: `Shared/Core/Services/CopyVerifyExecutor.swift`
- Modify: `BitMatch/Core/Services/ReportExporter.swift`
- Modify: `BitMatch/Views/ReportView.swift`
- Test: `BitMatchTests/PhotographerReportTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: authoritative job, card, grouping, and local result data from Tasks 1–6.
- Produces: photographer context in PDF, CSV, and enhanced JSON reports.

- [ ] **Step 1: Write failing report tests**

Cover JSON encoding of job/client/date/event, photographer/camera/card, rendered package path, preliminary and confirmed fingerprints, RAW/JPEG/sidecar counts, required local copies, verified destination count, `locallySafeAt`, warnings, and every result row. Construct the job, card, and two `ResultRow` values directly in the test: one `✅ Verified` RAW row with a checksum and one `⚠️ Checksum Missing` XMP row with a nil checksum. Assert the encoded payload identifies photographer `Mike`, camera `Sony A7 IV`, retains both rows, and classifies the XMP row as unsuccessful.

- [ ] **Step 2: Run RED**

Run `PhotographerReportTests` with DerivedData path `task-7`. Expected: compilation fails because `PhotographerReportPayload` does not exist.

- [ ] **Step 3: Add report context**

Add `PhotographerReportContext` and `PhotographerReportPayload` as Codable value types. `PhotographerReportContext` contains the complete `PhotographerJob`, active `cardIngestID`, its `CardAnalysis`, verified destination count, and warnings. `PhotographerReportPayload.make(context:results:) throws` selects the card by ID and maps every authoritative result without dropping failures. Add an optional `photographerContext` to `CopyVerifyConfig`. Pass it from `AppCoordinator` through `CopyVerifyExecutor` to `ReportExporter.export`. With a nil context, preserve the existing local-only report fields and meanings; only the intentional schema-version value changes.

- [ ] **Step 4: Extend exports and report UI**

Add a **Photography Job** section to PDF and JSON output. Add columns or fields for photographer, camera, card, and package-relative path. Include companion counts and duplicate findings in the summary. Keep all authoritative `ResultRow` objects; do not reconstruct success from displayed text.

Bump enhanced JSON `reportVersion` once and document the added optional object. CSV adds these columns after destination path: `Job`, `Photographer`, `Camera`, `Card`, `Package Path`.

- [ ] **Step 5: Verify focused report tests and existing report regressions**

Run `PhotographerReportTests`, `SharedReportGenerationSmokeTests`, `ResultStatusClassificationTests`, and `ResultsOverflowUpsertTests`. Expected: all pass.

- [ ] **Step 6: Run full release-grade validation**

Run:

```bash
DERIVED_DATA_ROOT="$PWD/.derived-data/photographer-phase-1/final" bash test.sh mac-test
DERIVED_DATA_ROOT="$PWD/.derived-data/photographer-phase-1/final" bash test.sh ipad-test
DERIVED_DATA_ROOT="$PWD/.derived-data/photographer-phase-1/final" bash test.sh release-builds
git diff --check
```

Run the iPad test command as `IOS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPad (A16),OS=latest' DERIVED_DATA_ROOT="$PWD/.derived-data/photographer-phase-1/final" bash test.sh ipad-test`. If that named simulator is absent, use the first available iPad name printed by `xcrun simctl list devices available` and record the selected destination in the implementation notes. Expected: macOS and iPad tests pass, both Release builds succeed, and `git diff --check` prints nothing.

- [ ] **Step 7: Update the changelog and commit**

Add an Unreleased section describing photographer jobs, preserved card packages, duplicate warnings, and photographer-aware reports.

```bash
git add Shared/Core/Models/PhotographerJobModels.swift \
  Shared/Core/Services/CopyVerifyExecutor.swift \
  BitMatch/Core/Services/ReportExporter.swift \
  BitMatch/Views/ReportView.swift \
  BitMatchTests/PhotographerReportTests.swift \
  CHANGELOG.md
git commit -m "feat: report photographer job provenance"
```

- [ ] **Step 8: Clean all generated data and verify the handoff**

```bash
rm -rf .derived-data/photographer-phase-1
git status -sb
git worktree list
du -sh .
df -h /
```

Expected: no generated DerivedData remains, the feature worktree contains only intentional source changes or is clean after commits, and disk usage is recorded before integration.

---

## Phase boundary

Phase 1 ends with local photographer jobs and no network code. The next implementation plan will consume these stable interfaces:

- `PhotographerJob` and `CardIngest` as the persistent job and card identity;
- immutable authoritative results and confirmed fingerprints;
- stable local package paths from `RenderedFolderRecipe`;
- independent local stage status;
- Core Data repository and migration pattern;
- photographer report context.

Phase 2 will add saved remote profiles, Keychain credentials, persistent queue items, SFTP, provider-aware verification, and the `Remote Queued` through `Fully Backed Up` states.
