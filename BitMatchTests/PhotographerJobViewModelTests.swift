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

    @Test func terminalStatesIgnoreDelayedProgressCancellationAndRepeatCompletion() throws {
        for terminalState in PhotographerLocalState.terminalStates {
            let store = InMemoryPhotographerJobStore()
            let viewModel = preparedViewModel(store: store)
            viewModel.beginIngest(destinationCount: 2)
            switch terminalState {
            case .locallySafe:
                try viewModel.completeIngest(results: verifiedRows(destinationNames: ["Primary", "Secondary"]))
            case .issues:
                try viewModel.completeIngest(results: verifiedRows(destinationNames: ["Primary"]))
            case .cancelled:
                viewModel.cancelIngest()
            default:
                Issue.record("Expected terminal state")
            }

            viewModel.updateProgressStage(.copying)
            viewModel.updateProgressStage(.verifying)
            viewModel.cancelIngest()
            try viewModel.completeIngest(results: verifiedRows(destinationNames: ["Primary", "Secondary"]))

            #expect(viewModel.activeCard?.localState == terminalState)
        }
    }

    @Test func equalDestinationCountsWithDifferentPathSetsAreIssues() throws {
        let viewModel = preparedViewModel(store: InMemoryPhotographerJobStore(), sourcePaths: ["/card/A.ARW", "/card/B.JPG"])
        viewModel.beginIngest(destinationCount: 2)
        let rows = [
            verifiedRow(path: "/card/A.ARW", checksum: "aaa", destination: "Primary"),
            verifiedRow(path: "/card/B.JPG", checksum: "bbb", destination: "Primary"),
            verifiedRow(path: "/card/A.ARW", checksum: "aaa", destination: "Secondary"),
            verifiedRow(path: "/card/C.JPG", checksum: "ccc", destination: "Secondary")
        ]

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .issues)
    }

    @Test func preparedPathMissingFromEveryResultIsIssues() throws {
        let viewModel = preparedViewModel(store: InMemoryPhotographerJobStore(), sourcePaths: ["/card/A.ARW", "/card/B.JPG"])
        viewModel.beginIngest(destinationCount: 2)
        let rows = ["Primary", "Secondary"].flatMap { destination in
            [verifiedRow(path: "/card/A.ARW", checksum: "aaa", destination: destination)]
        }

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .issues)
    }

    @Test func duplicateRowsForOneSourceAreIssues() throws {
        let viewModel = preparedViewModel(store: InMemoryPhotographerJobStore())
        viewModel.beginIngest(destinationCount: 2)
        var rows = verifiedRows(destinationNames: ["Primary", "Secondary"])
        rows.append(verifiedRow(path: "/card/A.ARW", checksum: "abc", destination: "Secondary"))

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .issues)
    }

    @Test func crossDestinationChecksumDisagreementIsIssues() throws {
        let viewModel = preparedViewModel(store: InMemoryPhotographerJobStore())
        viewModel.beginIngest(destinationCount: 2)
        let rows = [
            verifiedRow(path: "/card/A.ARW", checksum: "abc", destination: "Primary"),
            verifiedRow(path: "/card/A.ARW", checksum: "different", destination: "Secondary")
        ]

        try viewModel.completeIngest(results: rows)

        #expect(viewModel.activeCard?.localState == .issues)
    }

    @Test func blankSourceDestinationOrChecksumIsIssues() throws {
        let invalidRows = [
            verifiedRow(path: "   ", checksum: "abc", destination: "Primary"),
            ResultRow(path: "/card/A.ARW", status: "✅ Verified", size: 100, checksum: "abc", destination: "Primary", destinationPath: "  "),
            verifiedRow(path: "/card/A.ARW", checksum: " \t", destination: "Primary")
        ]

        for invalidRow in invalidRows {
            let viewModel = preparedViewModel(store: InMemoryPhotographerJobStore())
            viewModel.beginIngest(destinationCount: 2)
            try viewModel.completeIngest(results: [invalidRow, verifiedRow(path: "/card/A.ARW", checksum: "abc", destination: "Secondary")])
            #expect(viewModel.activeCard?.localState == .issues)
        }
    }

    @Test func safeTransitionPublishesOnlyAfterDurableSave() throws {
        let store = InMemoryPhotographerJobStore()
        let viewModel = preparedViewModel(store: store)
        viewModel.beginIngest(destinationCount: 2)
        viewModel.updateProgressStage(.verifying)
        store.errorOnSave = TestStoreError.saveFailed

        #expect(throws: TestStoreError.saveFailed) {
            try viewModel.completeIngest(results: verifiedRows(destinationNames: ["Primary", "Secondary"]))
        }

        #expect(viewModel.activeCard?.localState == .verifying)
        #expect(viewModel.activeCard?.locallySafeAt == nil)
        #expect(viewModel.lastError == TestStoreError.saveFailed.localizedDescription)
    }

    @Test func canonicalDestinationSelectionIsDeterministic() throws {
        var analyzedDestinationPaths: [[String]] = []
        let store = InMemoryPhotographerJobStore()
        let viewModel = PhotographerJobViewModel(
            store: store,
            now: { now },
            confirmedAnalyzer: { rows in
                analyzedDestinationPaths.append(rows.compactMap(\.destinationPath))
                return "confirmed"
            }
        )
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)
        try viewModel.prepareCard(photographerName: "Mike", cameraName: "Sony", analysis: analysis("preliminary"))
        viewModel.beginIngest(destinationCount: 2)
        let secondary = verifiedRow(path: "/card/A.ARW", checksum: "abc", destination: "Secondary")
        let primary = verifiedRow(path: "/card/A.ARW", checksum: "abc", destination: "Primary")

        try viewModel.completeIngest(results: [secondary, primary])

        #expect(analyzedDestinationPaths == [["/primary/A.ARW"]])
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

    private func preparedViewModel(
        store: InMemoryPhotographerJobStore,
        sourcePaths: [String] = ["/card/A.ARW"]
    ) -> PhotographerJobViewModel {
        let viewModel = makeViewModel(store: store)
        viewModel.createWeddingJob(clientName: "Smith", jobName: "Smith Wedding", eventDate: eventDate)
        try! viewModel.prepareCard(
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            analysis: analysis("preliminary", sourcePaths: sourcePaths)
        )
        return viewModel
    }

    private func analysis(_ fingerprint: String, sourcePaths: [String] = ["/card/A.ARW"]) -> CardAnalysis {
        CardAnalysis(fingerprint: fingerprint, fileCount: sourcePaths.count, totalBytes: 100, companionGroups: [], sourcePaths: sourcePaths)
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

    private func verifiedRow(path: String, checksum: String, destination: String) -> ResultRow {
        ResultRow(
            path: path,
            status: "✅ Verified",
            size: 100,
            checksum: checksum,
            destination: destination,
            destinationPath: "/\(destination.lowercased())/\((path as NSString).lastPathComponent)"
        )
    }
}

private extension PhotographerLocalState {
    static let terminalStates: [PhotographerLocalState] = [.locallySafe, .issues, .cancelled]
}

private enum TestStoreError: LocalizedError {
    case saveFailed

    var errorDescription: String? { "The test store rejected the save." }
}

@MainActor
final class InMemoryPhotographerJobStore: PhotographerJobStore {
    private(set) var storedJobs: [PhotographerJob] = []
    private(set) var storedPresets: [PhotographerPreset] = []
    private(set) var saveCount = 0
    var errorOnSave: Error?

    func jobs() throws -> [PhotographerJob] { storedJobs }

    func save(_ job: PhotographerJob) throws {
        if let errorOnSave { throw errorOnSave }
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
