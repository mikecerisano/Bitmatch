import Foundation
import Testing
@testable import BitMatch

@MainActor
struct PhotographerJobViewModelTests {
    private let eventDate = Date(timeIntervalSince1970: 100)
    private let now = Date(timeIntervalSince1970: 200)

    @Test func weddingJobUsesWeddingDefaultsAndPersistsCreation() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = makeViewModel(store: store)

        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)

        let job = try #require(viewModel.activeJob)
        #expect(job.eventType == .wedding)
        #expect(job.recipe.name == FolderRecipe.wedding.name)
        #expect(job.requiredLocalCopyCount == 2)
        #expect(job.clientName == "Smith")
        #expect(store.saveCount == 1)
        #expect(viewModel.jobs == [job])
    }

    @Test func cardNumbersAdvanceIndependentlyForEachCamera() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = makeViewModel(store: store)
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)

        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony A7 IV", analysis: analysis("one"))
        #expect(viewModel.activeCard?.provenance.cardNumber == 1)
        viewModel.resetForNextCard()
        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Canon R5", analysis: analysis("two"))
        #expect(viewModel.activeCard?.provenance.cardNumber == 1)
        viewModel.resetForNextCard()
        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony A7 IV", analysis: analysis("three"))

        #expect(viewModel.activeCard?.provenance.cardNumber == 2)
    }

    @Test func preparedCardPublishesRenderedPreviewAndPersistsNotStartedState() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = makeViewModel(store: store)
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)

        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony A7 IV", analysis: analysis("preview"))

        #expect(viewModel.renderedRecipe?.components == [
            "1970-01-01_Smith-Wedding", "Originals", "Mike", "Sony-A7-IV", "Card-001"
        ])
        #expect(viewModel.activeCardDraft?.localState == .notStarted)
        #expect(viewModel.activeCardDraft?.renderedRelativePath == viewModel.renderedRecipe?.relativePath)
        #expect(store.saveCount == 2)
    }

    @Test func preparedCardUsesHumanReadableDefaultSourceName() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = makeViewModel(store: store)
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)

        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony A7 IV", analysis: analysis("source"))

        #expect(viewModel.activeCard?.sourceDisplayName == "Card 1")
    }

    @Test func repeatedPreliminaryFingerprintPublishesPriorCardWarning() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = makeViewModel(store: store)
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)
        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony A7 IV", analysis: analysis("same"))
        let priorJobID = try #require(viewModel.activeJob?.id)
        let priorCardID = try #require(viewModel.activeCard?.id)
        viewModel.resetForNextCard()

        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony A7 IV", analysis: analysis("same"))

        let warning = try #require(viewModel.duplicateWarning)
        #expect(warning.jobID == priorJobID)
        #expect(warning.cardIngestID == priorCardID)
        #expect(warning.fingerprint == "same")
        #expect(warning.message.contains("already"))
    }

    @Test func ingestTransitionsCopyingVerifyingLocallySafeAndPersistsEachTransition() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        #expect(store.saveCount == 2)

        viewModel.beginIngest(destinationCount: 2)
        #expect(viewModel.activeCard?.localState == .copying)
        #expect(store.saveCount == 3)

        viewModel.updateProgressStage(.verifying)
        #expect(viewModel.activeCard?.localState == .verifying)
        #expect(store.saveCount == 4)

        try viewModel.completeIngest(results: verifiedRows(destinationNames: ["Primary", "Secondary"]))
        #expect(viewModel.activeCard?.localState == .locallySafe)
        #expect(viewModel.activeCard?.locallySafeAt == now)
        #expect(store.saveCount == 5)
    }

    @Test func completionRequiresConfiguredVerifiedDestinationCount() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)

        try viewModel.completeIngest(results: verifiedRows(destinationNames: ["Primary", "Secondary"]))

        #expect(viewModel.activeCard?.localState == .locallySafe)
    }

    @Test func startingWithTooFewDestinationsReportsRequiredCount() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)

        viewModel.beginIngest(destinationCount: 1)

        #expect(viewModel.lastError == "This job requires 2 verified local destinations.")
    }

    @Test func destinationPathsDistinguishVolumesWithTheSameDisplayName() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)
        let rows = ["/Volumes/One/Package/A.ARW", "/Volumes/Two/Package/A.ARW"].map { path in
            ResultRow(
                path: "/card/A.ARW",
                status: "✅ Verified",
                size: 100,
                checksum: "abc",
                destination: "Backup",
                destinationPath: path
            )
        }

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .locallySafe)
    }

    @Test func failedOrUnverifiedDestinationLeavesCardInIssues() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)
        let rows = verifiedRows(destinationNames: ["Primary"]) + [
            ResultRow(
                path: "/card/A.ARW",
                status: "❌ Checksum mismatch",
                size: 100,
                checksum: "bad",
                destination: "Secondary",
                destinationPath: "/secondary/A.ARW"
            )
        ]

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .issues)
        #expect(viewModel.activeCard?.locallySafeAt == nil)
    }

    @Test func successWithoutChecksumIsUnverifiedAndLeavesCardInIssues() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)
        let rows = verifiedRows(destinationNames: ["Primary"]) + [
            ResultRow(
                path: "/card/A.ARW",
                status: "✅ Copied",
                size: 100,
                checksum: nil,
                destination: "Secondary",
                destinationPath: "/secondary/A.ARW"
            )
        ]

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .issues)
    }

    @Test func safeCompletionStoresCardFingerprintFromOneAuthoritativeCopyPerSource() throws {
        let store = InMemoryPhotographerJobStore()
        let rows = verifiedRows(destinationNames: ["Primary", "Secondary"])
        let expected = try PhotographerCardAnalyzer.confirmedFingerprint(results: [rows[0]])
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.provenance.confirmedFingerprint == expected)
    }

    @Test func cancellationPersistsCancelledState() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)

        viewModel.cancelIngest()

        #expect(viewModel.activeCard?.localState == .cancelled)
        #expect(store.saveCount == 4)
    }

    @Test func resetClearsCardSpecificStateAndKeepsJobForNextCard() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        let jobID = viewModel.activeJob?.id

        viewModel.resetForNextCard()

        #expect(viewModel.activeJob?.id == jobID)
        #expect(viewModel.activeCardDraft == nil)
        #expect(viewModel.renderedRecipe == nil)
        #expect(viewModel.preliminaryAnalysis == nil)
        #expect(viewModel.duplicateWarning == nil)
        #expect(viewModel.cameraName.isEmpty)
    }

    private func makeViewModel(store: InMemoryPhotographerJobStore) -> PhotographerJobViewModel {
        PhotographerJobViewModel(store: store, now: { now })
    }

    private func preparedViewModel(store: InMemoryPhotographerJobStore) -> PhotographerJobViewModel {
        let viewModel = makeViewModel(store: store)
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)
        try! viewModel.prepareCard(
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            analysis: analysis("preliminary")
        )
        return viewModel
    }

    private func analysis(_ fingerprint: String) -> CardAnalysis {
        CardAnalysis(fingerprint: fingerprint, fileCount: 1, totalBytes: 100, companionGroups: [])
    }

    private func verifiedRows(destinationNames: [String]) -> [ResultRow] {
        destinationNames.map { destination in
            ResultRow(
                path: "/card/A.ARW",
                status: "✅ Verified",
                size: 100,
                checksum: "abc",
                destination: destination,
                destinationPath: "/\(destination.lowercased())/A.ARW"
            )
        }
    }
}

@MainActor
final class InMemoryPhotographerJobStore: PhotographerJobStore {
    private(set) var storedJobs: [PhotographerJob] = []
    private(set) var storedPresets: [PhotographerPreset] = []
    private(set) var saveCount = 0

    func jobs() throws -> [PhotographerJob] { storedJobs }

    func save(_ job: PhotographerJob) throws {
        saveCount += 1
        if let index = storedJobs.firstIndex(where: { $0.id == job.id }) {
            storedJobs[index] = job
        } else {
            storedJobs.append(job)
        }
    }

    func deleteJob(id: UUID) throws {
        storedJobs.removeAll { $0.id == id }
    }

    func presets() throws -> [PhotographerPreset] { storedPresets }

    func save(_ preset: PhotographerPreset) throws {
        if let index = storedPresets.firstIndex(where: { $0.id == preset.id }) {
            storedPresets[index] = preset
        } else {
            storedPresets.append(preset)
        }
    }
}
