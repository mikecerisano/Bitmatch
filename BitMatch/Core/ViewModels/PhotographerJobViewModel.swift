import Combine
import Foundation

struct DuplicateCardWarning: Equatable, Sendable {
    let jobID: UUID
    let cardIngestID: UUID
    let fingerprint: String
    let message: String

    var priorJobID: UUID { jobID }
    var priorCardIngestID: UUID { cardIngestID }
}

enum FolderLayerMoveDirection: Sendable {
    case up
    case down
}

@MainActor
final class PhotographerJobViewModel: ObservableObject {
    typealias PreliminaryAnalyzer = @Sendable ([FileEntry]) throws -> CardAnalysis
    typealias ConfirmedAnalyzer = @Sendable ([ResultRow]) throws -> String
    typealias EntryEnumerator = @Sendable (URL) throws -> [FileEntry]

    @Published private(set) var jobs: [PhotographerJob] = []
    @Published private(set) var presets: [PhotographerPreset] = []
    @Published private(set) var remoteProfiles: [RemoteDestinationProfile] = []
    @Published var activeJob: PhotographerJob?
    @Published var selectedPhotographerID: UUID?
    @Published var cameraName = ""
    @Published private(set) var activeCardDraft: CardIngest?
    @Published private(set) var renderedRecipe: RenderedFolderRecipe?
    @Published private(set) var preliminaryAnalysis: CardAnalysis?
    @Published private(set) var duplicateWarning: DuplicateCardWarning?
    @Published private(set) var lastError: String?
    @Published var draftRecipe = FolderRecipe.wedding
    @Published var focusedCardIngestID: UUID?
    @Published private(set) var dashboardJobID: UUID?
    @Published private(set) var isPreparing = false
    @Published private(set) var preparationError: String?

    var activeCard: CardIngest? {
        guard let id = activeCardDraft?.id else { return nil }
        return activeJob?.cardIngests.first { $0.id == id }
    }

    /// A photographer card changes the transfer contract only while it is
    /// deliberately prepared and waiting to begin. Completed or failed cards
    /// remain visible in the dashboard, but never block ordinary transfers.
    var hasPreparedIngestAwaitingStart: Bool {
        activeCard?.localState == .notStarted
    }

    var dashboardJob: PhotographerJob? {
        guard let dashboardJobID else { return activeJob }
        if activeJob?.id == dashboardJobID { return activeJob }
        return jobs.first { $0.id == dashboardJobID }
    }

    private let store: any PhotographerJobStore
    private let now: () -> Date
    private let preliminaryAnalyzer: PreliminaryAnalyzer
    private let confirmedAnalyzer: ConfirmedAnalyzer
    private let entryEnumerator: EntryEnumerator
    private let remoteBackupCoordinator: RemoteBackupCoordinator
    private var preparedSourcePath: String?
    private var currentSourcePath: String?
    private var preparedSetupSignature: PhotographerSetupSignature?
    private var currentSetupSignature: PhotographerSetupSignature?
    private var sourcePreparationInvalidated = false
    private var setupPreparationInvalidated = false
    private var setupTask: Task<Void, Never>?
    private var setupGeneration = UUID()

    init(
        store: any PhotographerJobStore,
        now: @escaping () -> Date = Date.init,
        preliminaryAnalyzer: @escaping PreliminaryAnalyzer = PhotographerCardAnalyzer.preliminaryAnalysis,
        confirmedAnalyzer: @escaping ConfirmedAnalyzer = PhotographerCardAnalyzer.confirmedFingerprint,
        entryEnumerator: @escaping EntryEnumerator = FileTreeEnumerator.enumerateRegularFiles,
        remoteBackupCoordinator: RemoteBackupCoordinator? = nil
    ) {
        self.store = store
        self.now = now
        self.preliminaryAnalyzer = preliminaryAnalyzer
        self.confirmedAnalyzer = confirmedAnalyzer
        self.entryEnumerator = entryEnumerator
        self.remoteBackupCoordinator = remoteBackupCoordinator ?? RemoteBackupCoordinator(store: store)
        loadJobs()
        loadPresets()
        loadRemoteProfiles()
        if !store.isAvailable {
            store.whenAvailable { [weak self] in
                guard let self else { return }
                self.loadJobs()
                self.loadPresets()
                self.loadRemoteProfiles()
            }
        }
    }

    func createWeddingJob(clientName: String, jobName: String, eventDate: Date) {
        let timestamp = now()
        let job = PhotographerJob(
            id: UUID(),
            eventDate: eventDate,
            clientName: clientName,
            jobName: jobName,
            eventType: .wedding,
            photographers: [],
            recipe: draftRecipe,
            requiredLocalCopyCount: 2,
            cardIngests: [],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        do {
            try persistThrowing(job)
            clearCardPreparation()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func prepareCard(
        photographerName: String,
        cameraName: String,
        sourceDisplayName: String? = nil,
        analysis: CardAnalysis
    ) throws {
        guard var job = activeJob else {
            throw PhotographerJobViewModelError.noActiveJob
        }

        let photographer = identity(named: photographerName, in: job)
        if !job.photographers.contains(where: { $0.id == photographer.id }) {
            job.photographers.append(photographer)
        }

        let pendingIndex = activeCardDraft.flatMap { draft in
            job.cardIngests.firstIndex { $0.id == draft.id && $0.localState == .notStarted }
        }
        let pendingCard = pendingIndex.map { job.cardIngests[$0] }
        let cardNumber = pendingCard?.provenance.cardNumber
            ?? nextCardNumber(cameraName: cameraName, in: job)
        let rendered = try FolderRecipeRenderer.render(
            job.recipe,
            context: FolderRecipeContext(
                eventDate: job.eventDate,
                jobName: job.jobName,
                photographer: photographer.name,
                camera: cameraName,
                cardNumber: cardNumber
            )
        )
        if job.cardIngests.contains(where: { card in
            card.id != pendingCard?.id
                && portablePackageRoute(card.renderedRelativePath)
                    == portablePackageRoute(rendered.relativePath)
        }) {
            throw PhotographerJobViewModelError.duplicatePackageRoute(rendered.relativePath)
        }
        let warning = duplicateWarning(
            for: analysis.fingerprint,
            excludingCardID: pendingCard?.id
        )
        let card = CardIngest(
            id: pendingCard?.id ?? UUID(),
            provenance: CardProvenance(
                photographerID: photographer.id,
                photographerName: photographer.name,
                cameraName: cameraName,
                cardNumber: cardNumber,
                preliminaryFingerprint: analysis.fingerprint,
                confirmedFingerprint: nil
            ),
            sourceDisplayName: sourceDisplayName ?? "Card " + String(cardNumber),
            renderedRelativePath: rendered.relativePath,
            localState: .notStarted,
            startedAt: nil,
            locallySafeAt: nil,
            fileCount: analysis.fileCount,
            totalBytes: analysis.totalBytes
        )

        if let pendingIndex {
            job.cardIngests[pendingIndex] = card
        } else {
            job.cardIngests.append(card)
        }
        try persistThrowing(job)
        selectedPhotographerID = photographer.id
        self.cameraName = cameraName
        activeCardDraft = card
        renderedRecipe = rendered
        preliminaryAnalysis = analysis
        duplicateWarning = warning
        let signature = PhotographerSetupSignature(
            clientName: job.clientName,
            jobName: job.jobName,
            eventDate: job.eventDate,
            photographerName: photographer.name,
            cameraName: cameraName,
            cardNumber: cardNumber,
            recipe: job.recipe
        )
        currentSetupSignature = signature
        preparedSetupSignature = signature
    }

    func prepareCard(
        photographerName: String,
        cameraName: String,
        sourceURL: URL,
        setupSignature: PhotographerSetupSignature,
        analysis: CardAnalysis
    ) throws {
        currentSetupSignature = setupSignature
        currentSourcePath = standardizedPath(sourceURL)
        try prepareCard(
            photographerName: photographerName,
            cameraName: cameraName,
            sourceDisplayName: sourceURL.lastPathComponent,
            analysis: analysis
        )
        preparedSourcePath = standardizedPath(sourceURL)
        let actualSignature = preparedSetupSignature ?? setupSignature
        preparedSetupSignature = actualSignature
        currentSetupSignature = actualSignature
        sourcePreparationInvalidated = false
        setupPreparationInvalidated = false
    }

    func prepareDraftCard(
        clientName: String,
        jobName: String,
        eventDate: Date,
        photographerName: String,
        cameraName: String,
        sourceDisplayName: String,
        entries: [FileEntry]
    ) throws {
        if var job = activeJob,
           job.clientName == clientName,
           job.jobName == jobName,
           job.eventDate == eventDate,
           job.eventType == .wedding {
            job.recipe = draftRecipe
            try persistThrowing(job)
        } else {
            createWeddingJob(clientName: clientName, jobName: jobName, eventDate: eventDate)
        }
        try prepareCard(
            photographerName: photographerName,
            cameraName: cameraName,
            sourceDisplayName: sourceDisplayName,
            entries: entries
        )
    }

    func startPreparingDraftCard(sourceURL: URL, setupSignature: PhotographerSetupSignature) {
        guard !isPreparing else { return }
        setupTask?.cancel()
        let generation = UUID()
        setupGeneration = generation
        isPreparing = true
        preparationError = nil
        currentSetupSignature = setupSignature
        let enumerator = entryEnumerator
        let analyzer = preliminaryAnalyzer
        let standardizedSource = sourceURL.standardizedFileURL
        currentSourcePath = standardizedPath(standardizedSource)
        setupTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    let entries = try enumerator(standardizedSource)
                    try Task.checkCancellation()
                    return Result<CardAnalysis, Error>.success(try analyzer(entries))
                } catch {
                    return .failure(error)
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.setupGeneration == generation else { return }
            self.isPreparing = false
            self.setupTask = nil
            guard self.currentSetupSignature == setupSignature,
                  self.standardizedPath(standardizedSource) == self.currentSourcePath else { return }
            switch result {
            case .success(let analysis):
                do {
                    try self.prepareDraftCard(analysis: analysis, sourceURL: standardizedSource, setupSignature: setupSignature)
                    self.preparationError = nil
                } catch {
                    self.preparationError = error.localizedDescription
                }
            case .failure(let error):
                if !(error is CancellationError) { self.preparationError = error.localizedDescription }
            }
        }
    }

    private func prepareDraftCard(
        analysis: CardAnalysis,
        sourceURL: URL,
        setupSignature: PhotographerSetupSignature
    ) throws {
        if var job = activeJob, activeCard?.localState == .notStarted {
            job.clientName = setupSignature.clientName
            job.jobName = setupSignature.jobName
            job.eventDate = setupSignature.eventDate
            job.eventType = .wedding
            job.recipe = setupSignature.recipe
            try persistThrowing(job)
        } else if var job = activeJob,
                  job.clientName == setupSignature.clientName,
                  job.jobName == setupSignature.jobName,
                  job.eventDate == setupSignature.eventDate,
                  job.eventType == .wedding {
            job.recipe = setupSignature.recipe
            try persistThrowing(job)
        } else {
            draftRecipe = setupSignature.recipe
            createWeddingJob(clientName: setupSignature.clientName, jobName: setupSignature.jobName, eventDate: setupSignature.eventDate)
        }
        try prepareCard(
            photographerName: setupSignature.photographerName,
            cameraName: setupSignature.cameraName,
            sourceURL: sourceURL,
            setupSignature: setupSignature,
            analysis: analysis
        )
    }

    func waitForSetupForTesting() async {
        let task = setupTask
        await task?.value
    }

    func proposedCardNumber(cameraName: String) -> Int {
        if let activeCardDraft {
            return activeCardDraft.provenance.cardNumber
        }
        guard let activeJob else { return 1 }
        return nextCardNumber(cameraName: cameraName, in: activeJob)
    }

    func prepareCard(
        photographerName: String,
        cameraName: String,
        sourceDisplayName: String? = nil,
        entries: [FileEntry]
    ) throws {
        try prepareCard(
            photographerName: photographerName,
            cameraName: cameraName,
            sourceDisplayName: sourceDisplayName,
            analysis: preliminaryAnalyzer(entries)
        )
    }

    @discardableResult
    func beginIngest(
        destinationCount: Int,
        sourceURL: URL? = nil,
        verificationMode: VerificationMode = .standard
    ) -> Bool {
        guard activeJob != nil else { return false }
        let presentation = startPresentation(
            preflightReady: true,
            sourceURL: sourceURL,
            destinationCount: destinationCount,
            verificationMode: verificationMode
        )
        guard presentation.canStart else {
            lastError = presentation.blocker
            return false
        }
        transitionActiveCard(to: .copying) { card in
            if card.startedAt == nil { card.startedAt = self.now() }
            card.locallySafeAt = nil
        }
        lastError = nil
        return activeCard?.localState == .copying
    }

    func updateSetupSignature(_ signature: PhotographerSetupSignature) {
        if let preparedSetupSignature, preparedSetupSignature != signature {
            setupPreparationInvalidated = true
        }
        currentSetupSignature = signature
    }

    func sourceDidChange(to sourceURL: URL?) {
        let newPath = sourceURL.map(standardizedPath)
        currentSourcePath = newPath
        if let preparedSourcePath, preparedSourcePath != newPath {
            sourcePreparationInvalidated = true
        }
        if isPreparing || (preparedSourcePath != nil && preparedSourcePath != newPath) {
            setupGeneration = UUID()
            setupTask?.cancel()
            isPreparing = false
        }
    }

    func startPresentation(
        preflightReady: Bool,
        sourceURL: URL?,
        destinationCount: Int,
        verificationMode: VerificationMode = .standard
    ) -> PhotographerStartPresentation {
        let sourceMatches = !sourcePreparationInvalidated && (preparedSourcePath == sourceURL.map(standardizedPath)
            || (preparedSourcePath == nil && sourceURL == nil)
        )
        return PhotographerStartPresentation.make(context: PhotographerStartContext(
            preflightReady: preflightReady,
            isPreparing: isPreparing,
            activeCardState: activeCard?.localState,
            sourceMatches: sourceMatches,
            setupMatches: !setupPreparationInvalidated
                && preparedSetupSignature != nil
                && preparedSetupSignature == currentSetupSignature,
            destinationCount: destinationCount,
            requiredDestinationCount: activeJob?.requiredLocalCopyCount ?? 0,
            verificationMode: verificationMode
        ))
    }

    func isStartEligible(
        preflightReady: Bool,
        sourceURL: URL?,
        destinationCount: Int,
        verificationMode: VerificationMode = .standard
    ) -> Bool {
        startPresentation(
            preflightReady: preflightReady,
            sourceURL: sourceURL,
            destinationCount: destinationCount,
            verificationMode: verificationMode
        ).canStart
    }

    func updateProgressStage(_ stage: ProgressStage) {
        switch stage {
        case .copying:
            transitionActiveCard(to: .copying) { card in
                if card.startedAt == nil { card.startedAt = self.now() }
            }
        case .verifying:
            transitionActiveCard(to: .verifying)
        default:
            break
        }
    }

    func operationFailed() {
        do {
            try transitionActiveCardThrowing(to: .issues) { card in
                card.locallySafeAt = nil
                card.provenance.confirmedFingerprint = nil
                card.verifiedDestinationCount = 0
            }
        } catch {
            forceActiveCardIntoIssuesInMemory()
            lastError = error.localizedDescription
        }
    }

    /// Remote controls deliberately update only remote configuration and
    /// summaries. A remote error must never invalidate local copy evidence.
    func selectRemoteProfile(_ profileID: UUID?) {
        guard let jobID = activeJob?.id else {
            lastError = RemoteBackupError.manifestUnavailable.errorDescription
            return
        }
        do {
            let updatedJob = try remoteBackupCoordinator.selectRemoteProfile(profileID, for: jobID)
            replaceLoadedJob(updatedJob)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func queueRemoteBackup(for cardIngestID: UUID, results: [ResultRow]) throws -> [RemoteQueueItem] {
        guard let jobID = activeJob?.id else { throw PhotographerJobViewModelError.noActiveJob }
        do {
            let items = try remoteBackupCoordinator.queueRemoteBackup(
                for: cardIngestID,
                in: jobID,
                results: results
            )
            try updateRemoteSummary(for: cardIngestID, items: items)
            lastError = nil
            return items
        } catch {
            // Do not call operationFailed(): the local verdict was produced
            // by the authoritative local operation and remains unchanged.
            lastError = error.localizedDescription
            throw error
        }
    }

    func pauseRemoteBackup(for cardIngestID: UUID) {
        guard let jobID = activeJob?.id else { return }
        do {
            let items = try remoteBackupCoordinator.pauseRemoteBackup(for: cardIngestID, in: jobID)
            try updateRemoteSummary(for: cardIngestID, items: items)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func retryRemoteBackup(for cardIngestID: UUID) {
        guard let jobID = activeJob?.id else { return }
        do {
            let items = try remoteBackupCoordinator.retryRemoteBackup(for: cardIngestID, in: jobID)
            try updateRemoteSummary(for: cardIngestID, items: items)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Queue workers persist the authoritative remote state. Rebuild the card
    /// summary from those durable items after a run without touching local
    /// safety evidence.
    func refreshRemoteBackupSummary(for cardIngestID: UUID, items: [RemoteQueueItem]) {
        do {
            try updateRemoteSummary(for: cardIngestID, items: items)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func completeIngest(results: [ResultRow]) throws -> PhotographerFinalizationResult {
        guard var job = activeJob else {
            throw PhotographerJobViewModelError.noActiveJob
        }
        guard let cardID = activeCardDraft?.id,
              let cardIndex = job.cardIngests.firstIndex(where: { $0.id == cardID }) else {
            throw PhotographerJobViewModelError.noActiveCard
        }
        guard let analysis = preliminaryAnalysis else {
            throw PhotographerJobViewModelError.missingPreliminaryAnalysis
        }
        let currentCard = job.cardIngests[cardIndex]
        guard currentCard.localState == .copying || currentCard.localState == .verifying else {
            return finalizationResult(job: job, cardID: cardID, analysis: analysis)
        }

        let context = PhotographerReportContext(
            job: job,
            cardIngestID: cardID,
            analysis: analysis,
            verifiedDestinationCount: currentCard.verifiedDestinationCount,
            warnings: duplicateWarning.map { [$0.message] } ?? []
        )
        let finalized: PhotographerReportPayload.FinalizedCard
        do {
            finalized = try PhotographerReportPayload.finalizedCard(
                context: context,
                results: results,
                finishedAt: now(),
                confirmedFingerprint: confirmedAnalyzer
            )
        } catch {
            var failedCard = currentCard
            failedCard.localState = .issues
            failedCard.locallySafeAt = nil
            failedCard.provenance.confirmedFingerprint = nil
            failedCard.verifiedDestinationCount = 0
            job.cardIngests[cardIndex] = failedCard
            do {
                try persistThrowing(job)
            } catch {
                lastError = error.localizedDescription
                throw error
            }
            activeCardDraft = failedCard
            lastError = error.localizedDescription
            throw error
        }

        job.cardIngests[cardIndex] = finalized.card
        do {
            try persistThrowing(job)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        activeCardDraft = finalized.card
        return finalizationResult(
            job: activeJob ?? job,
            cardID: cardID,
            analysis: analysis
        )
    }

    func cancelIngest() {
        transitionActiveCard(to: .cancelled) { card in
            card.locallySafeAt = nil
        }
    }

    private func updateRemoteSummary(for cardIngestID: UUID, items: [RemoteQueueItem]) throws {
        guard !items.isEmpty,
              var job = activeJob,
              let cardIndex = job.cardIngests.firstIndex(where: { $0.id == cardIngestID }) else { return }
        let targetID = items[0].destinationProfileID
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.uploadedByteCount }
        let expectedBytes = try items.reduce(Int64(0)) { (total, item) throws -> Int64 in
            total + (try remoteManifestEntryByteCount(for: item))
        }
        let state = items.contains(where: { $0.state == .paused }) ? RemoteBackupState.paused
            : items.contains(where: { $0.state == .retrying }) ? .retrying
            : items.contains(where: { $0.state == .uploading }) ? .uploading
            : items.contains(where: { $0.state == .queued }) ? .queued
            : items[0].state
        job.cardIngests[cardIndex].remoteBackupSummaries[targetID] = RemoteBackupCardSummary(
            targetID: targetID,
            state: state,
            totalFileCount: items.count,
            uploadedFileCount: items.filter { $0.state == .uploadedUnverified || $0.state == .verified }.count,
            totalByteCount: expectedBytes,
            uploadedByteCount: totalBytes,
            verificationEvidence: items.first?.verificationEvidence ?? .none,
            remotePath: items.first?.remoteRelativePath,
            errorSummary: items.compactMap(\.errorSummary).first,
            updatedAt: now()
        )
        try persistThrowing(job)
    }

    private func remoteManifestEntryByteCount(for item: RemoteQueueItem) throws -> Int64 {
        guard let manifest = try store.manifests().first(where: { $0.id == item.manifestID }),
              let entry = manifest.entries.first(where: { $0.id == item.manifestEntryID }) else {
            throw RemoteBackupError.manifestUnavailable
        }
        return entry.byteCount
    }

    private func replaceLoadedJob(_ updatedJob: PhotographerJob) {
        if let index = jobs.firstIndex(where: { $0.id == updatedJob.id }) {
            jobs[index] = updatedJob
        } else {
            jobs.append(updatedJob)
        }
        activeJob = updatedJob
    }

    func resetForNextCard() {
        clearCardPreparation()
    }

    func setDraftLayer(_ id: UUID, isEnabled: Bool) {
        guard let index = draftRecipe.layers.firstIndex(where: { $0.id == id }) else { return }
        draftRecipe.layers[index].isEnabled = isEnabled
        invalidateSetupPreparationIfNeeded()
    }

    func moveDraftLayer(_ id: UUID, direction: FolderLayerMoveDirection) {
        guard let index = draftRecipe.layers.firstIndex(where: { $0.id == id }) else { return }
        let destination = direction == .up ? index - 1 : index + 1
        guard draftRecipe.layers.indices.contains(destination) else { return }
        draftRecipe.layers.swapAt(index, destination)
        invalidateSetupPreparationIfNeeded()
    }

    func saveDraftAsPreset(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let presetID = UUID()
        var recipe = draftRecipe
        recipe.id = presetID
        recipe.name = cleanName
        let preset = PhotographerPreset(
            id: presetID,
            name: cleanName,
            eventType: .wedding,
            recipe: recipe,
            requiredLocalCopyCount: activeJob?.requiredLocalCopyCount ?? 2
        )
        do {
            try store.save(preset)
            presets.append(preset)
            presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            draftRecipe = recipe
            invalidateSetupPreparationIfNeeded()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectPreset(id: UUID) {
        if id == FolderRecipe.wedding.id {
            draftRecipe = .wedding
        } else if let preset = presets.first(where: { $0.id == id }) {
            draftRecipe = preset.recipe
        }
        invalidateSetupPreparationIfNeeded()
    }

    func focusCardIngest(id: UUID) {
        dashboardJobID = jobs.first { job in
            job.cardIngests.contains { $0.id == id }
        }?.id ?? activeJob.flatMap { job in
            job.cardIngests.contains { $0.id == id } ? job.id : nil
        }
        focusedCardIngestID = id
    }

    private func loadJobs() {
        do {
            var recoveredCardCount = 0
            let loadedJobs = try store.jobs()
            let recoveredJobs = try loadedJobs.map { job -> PhotographerJob in
                var recovered = job
                var changed = false

                for index in recovered.cardIngests.indices where [
                    PhotographerLocalState.notStarted,
                    .copying,
                    .verifying
                ].contains(recovered.cardIngests[index].localState) {
                    recovered.cardIngests[index].localState = .issues
                    recovered.cardIngests[index].locallySafeAt = nil
                    recovered.cardIngests[index].provenance.confirmedFingerprint = nil
                    recovered.cardIngests[index].verifiedDestinationCount = 0
                    recoveredCardCount += 1
                    changed = true
                }

                if changed {
                    recovered.updatedAt = now()
                    try store.save(recovered)
                }
                return recovered
            }

            jobs = recoveredJobs.sorted { $0.updatedAt > $1.updatedAt }
            activeJob = jobs.first
            dashboardJobID = activeJob?.id
            if recoveredCardCount > 0 {
                lastError = "Recovered \(recoveredCardCount) interrupted photographer \(recoveredCardCount == 1 ? "card" : "cards") and marked them as issues. Set up a new card to retry."
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadPresets() {
        do {
            presets = try store.presets().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadRemoteProfiles() {
        do {
            remoteProfiles = try store.profiles().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            remoteProfiles = []
        }
    }

    private func identity(named name: String, in job: PhotographerJob) -> PhotographerIdentity {
        if let existing = job.photographers.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return existing
        }
        return PhotographerIdentity(id: UUID(), name: name)
    }

    private func nextCardNumber(cameraName: String, in job: PhotographerJob) -> Int {
        let priorNumbers = job.cardIngests.compactMap { card -> Int? in
            guard card.provenance.cameraName.compare(
                cameraName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame else { return nil }
            return card.provenance.cardNumber
        }
        return (priorNumbers.max() ?? 0) + 1
    }

    private func portablePackageRoute(_ route: String) -> String {
        route
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component)
                    .precomposedStringWithCanonicalMapping
                    .lowercased(with: Locale(identifier: "en_US_POSIX"))
            }
            .joined(separator: "/")
    }

    private func duplicateWarning(
        for fingerprint: String,
        excludingCardID: UUID? = nil
    ) -> DuplicateCardWarning? {
        let currentJobID = activeJob?.id
        let allJobs = jobs.map { storedJob in
            storedJob.id == currentJobID ? (activeJob ?? storedJob) : storedJob
        }
        for job in allJobs {
            if let card = job.cardIngests.first(where: {
                $0.id != excludingCardID
                    && ($0.provenance.preliminaryFingerprint == fingerprint
                        || $0.provenance.confirmedFingerprint == fingerprint)
            }) {
                return DuplicateCardWarning(
                    jobID: job.id,
                    cardIngestID: card.id,
                    fingerprint: fingerprint,
                    message: "This card appears to have already been ingested for \(job.jobName)."
                )
            }
        }
        return nil
    }

    private func finalizationResult(
        job: PhotographerJob,
        cardID: UUID,
        analysis: CardAnalysis
    ) -> PhotographerFinalizationResult {
        let card = job.cardIngests.first { $0.id == cardID }
        let context = PhotographerReportContext(
            job: job,
            cardIngestID: cardID,
            analysis: analysis,
            verifiedDestinationCount: card?.verifiedDestinationCount ?? 0,
            warnings: duplicateWarning.map { [$0.message] } ?? []
        )
        return PhotographerFinalizationResult(
            context: context,
            locallySafe: card?.localState == .locallySafe
        )
    }

    private func transitionActiveCard(
        to state: PhotographerLocalState,
        mutate: (inout CardIngest) -> Void = { _ in }
    ) {
        do {
            try transitionActiveCardThrowing(to: state, mutate: mutate)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func transitionActiveCardThrowing(
        to state: PhotographerLocalState,
        mutate: (inout CardIngest) -> Void = { _ in }
    ) throws {
        guard var job = activeJob,
              let cardID = activeCardDraft?.id,
              let index = job.cardIngests.firstIndex(where: { $0.id == cardID }) else { return }
        let currentState = job.cardIngests[index].localState
        guard currentState != state, canTransition(from: currentState, to: state) else { return }

        job.cardIngests[index].localState = state
        mutate(&job.cardIngests[index])
        do {
            try persistThrowing(job)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        activeCardDraft = job.cardIngests[index]
    }

    private func forceActiveCardIntoIssuesInMemory() {
        guard var job = activeJob,
              let cardID = activeCardDraft?.id,
              let index = job.cardIngests.firstIndex(where: { $0.id == cardID }) else { return }
        guard job.cardIngests[index].localState == .notStarted
                || job.cardIngests[index].localState == .copying
                || job.cardIngests[index].localState == .verifying else { return }

        job.cardIngests[index].localState = .issues
        job.cardIngests[index].locallySafeAt = nil
        job.cardIngests[index].provenance.confirmedFingerprint = nil
        job.cardIngests[index].verifiedDestinationCount = 0
        activeJob = job
        if let jobIndex = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[jobIndex] = job
        }
        activeCardDraft = job.cardIngests[index]
    }

    private func persistThrowing(_ job: PhotographerJob) throws {
        var updated = job
        updated.updatedAt = now()
        try store.save(updated)
        activeJob = updated
        if let index = jobs.firstIndex(where: { $0.id == updated.id }) {
            jobs[index] = updated
        } else {
            jobs.append(updated)
        }
        jobs.sort { $0.updatedAt > $1.updatedAt }
        lastError = nil
    }

    private func canTransition(from current: PhotographerLocalState, to next: PhotographerLocalState) -> Bool {
        switch current {
        case .locallySafe, .issues, .cancelled:
            return false
        case .notStarted:
            return next == .copying || next == .issues || next == .cancelled
        case .copying:
            return next == .verifying || next == .locallySafe || next == .issues || next == .cancelled
        case .verifying:
            return next == .locallySafe || next == .issues || next == .cancelled
        }
    }

    private func clearCardPreparation() {
        selectedPhotographerID = nil
        cameraName = ""
        activeCardDraft = nil
        renderedRecipe = nil
        preliminaryAnalysis = nil
        duplicateWarning = nil
        preparedSourcePath = nil
        preparedSetupSignature = nil
        currentSetupSignature = nil
        currentSourcePath = nil
        sourcePreparationInvalidated = false
        setupPreparationInvalidated = false
        setupGeneration = UUID()
        setupTask?.cancel()
        setupTask = nil
        isPreparing = false
        preparationError = nil
        lastError = nil
    }

    private func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func invalidateSetupPreparationIfNeeded() {
        if preparedSetupSignature != nil {
            setupPreparationInvalidated = true
        }
    }

}

enum PhotographerJobViewModelError: LocalizedError, Equatable {
    case noActiveJob
    case noActiveCard
    case missingPreliminaryAnalysis
    case duplicatePackageRoute(String)

    var errorDescription: String? {
        switch self {
        case .noActiveJob: return "Create or select a photographer job first."
        case .noActiveCard: return "Prepare a photographer card before completing ingest."
        case .missingPreliminaryAnalysis: return "Card analysis is required before completing ingest."
        case .duplicatePackageRoute(let path):
            return "Another card in this job already uses the package route \(path). Change the folder layers before retrying."
        }
    }
}
