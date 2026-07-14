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
        entryEnumerator: @escaping EntryEnumerator = FileTreeEnumerator.enumerateRegularFiles
    ) {
        self.store = store
        self.now = now
        self.preliminaryAnalyzer = preliminaryAnalyzer
        self.confirmedAnalyzer = confirmedAnalyzer
        self.entryEnumerator = entryEnumerator
        loadJobs()
        loadPresets()
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

        let cardNumber = nextCardNumber(cameraName: cameraName, in: job)
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
        let warning = duplicateWarning(for: analysis.fingerprint)
        let card = CardIngest(
            id: UUID(),
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

        job.cardIngests.append(card)
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
        preparedSetupSignature = setupSignature
        currentSetupSignature = setupSignature
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
        if var job = activeJob,
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
    func beginIngest(destinationCount: Int, sourceURL: URL? = nil) -> Bool {
        guard let job = activeJob,
              isStartEligible(preflightReady: true, sourceURL: sourceURL, destinationCount: destinationCount) else {
            if let required = activeJob?.requiredLocalCopyCount, destinationCount < required {
                lastError = PhotographerStartPresentation.insufficientDestinationError(requiredCount: required)
            }
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

    func startPresentation(preflightReady: Bool, sourceURL: URL?, destinationCount: Int) -> PhotographerStartPresentation {
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
            requiredDestinationCount: activeJob?.requiredLocalCopyCount ?? 0
        ))
    }

    func isStartEligible(preflightReady: Bool, sourceURL: URL?, destinationCount: Int) -> Bool {
        startPresentation(preflightReady: preflightReady, sourceURL: sourceURL, destinationCount: destinationCount).canStart
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
        transitionActiveCard(to: .issues) { card in
            card.locallySafeAt = nil
            card.provenance.confirmedFingerprint = nil
        }
    }

    func completeIngest(results: [ResultRow]) throws {
        guard let requiredCount = activeJob?.requiredLocalCopyCount,
              !isActiveCardTerminal else { return }
        let expectedPaths = preliminaryAnalysis?.sourcePaths ?? []
        let expectedSet = Set(expectedPaths)
        let identifiedRows = results.compactMap { row -> (String, ResultRow)? in
            guard let identity = destinationIdentity(for: row) else { return nil }
            return (identity, row)
        }
        let groups = Dictionary(grouping: identifiedRows, by: \.0)
            .mapValues { $0.map(\.1) }
        let manifests = groups.mapValues { rows in
            rows.reduce(into: [String: String]()) { manifest, row in
                manifest[row.path] = row.checksum ?? ""
            }
        }
        let hasExactEvidence = !expectedPaths.isEmpty
            && expectedSet.count == expectedPaths.count
            && expectedPaths.count == activeCard?.fileCount
            && identifiedRows.count == results.count
            && groups.count >= requiredCount
            && groups.values.allSatisfy { rows in
                rows.count == expectedPaths.count
                    && Set(rows.map(\.path)) == expectedSet
                    && rows.allSatisfy(isVerified)
            }
        let checksumsAgree = expectedPaths.allSatisfy { path in
            let checksums = Set(manifests.values.compactMap { $0[path] })
            return checksums.count == 1 && checksums.first?.isEmpty == false
        }

        guard hasExactEvidence, checksumsAgree else {
            operationFailed()
            return
        }

        let canonicalRows = groups.sorted { $0.key < $1.key }.first?.value.sorted { $0.path < $1.path } ?? []
        let fingerprint: String
        do {
            fingerprint = try confirmedAnalyzer(canonicalRows)
        } catch {
            operationFailed()
            throw error
        }
        try transitionActiveCardThrowing(to: .locallySafe) { card in
            card.locallySafeAt = self.now()
            card.provenance.confirmedFingerprint = fingerprint
            card.verifiedDestinationCount = groups.count
        }
    }

    func cancelIngest() {
        transitionActiveCard(to: .cancelled) { card in
            card.locallySafeAt = nil
        }
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
            jobs = try store.jobs().sorted { $0.updatedAt > $1.updatedAt }
            activeJob = jobs.first
            dashboardJobID = activeJob?.id
            lastError = nil
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

    private func duplicateWarning(for fingerprint: String) -> DuplicateCardWarning? {
        let currentJobID = activeJob?.id
        let allJobs = jobs.map { storedJob in
            storedJob.id == currentJobID ? (activeJob ?? storedJob) : storedJob
        }
        for job in allJobs {
            if let card = job.cardIngests.first(where: {
                $0.provenance.preliminaryFingerprint == fingerprint
                    || $0.provenance.confirmedFingerprint == fingerprint
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

    private func destinationIdentity(for row: ResultRow) -> String? {
        if let destinationPath = nonblank(row.destinationPath) {
            let pathComponents = URL(fileURLWithPath: destinationPath).standardized.pathComponents
            if let recipeComponents = renderedRecipe?.components,
               let recipeStart = pathComponents.firstSubsequenceIndex(of: recipeComponents) {
                let packageEnd = recipeStart + recipeComponents.count
                return NSString.path(withComponents: Array(pathComponents[..<packageEnd]))
            }
            return URL(fileURLWithPath: destinationPath).standardized.deletingLastPathComponent().path
        }
        if let destination = nonblank(row.destination) {
            return destination
        }
        return nil
    }

    private func isVerified(_ row: ResultRow) -> Bool {
        row.isSuccessStatus
            && nonblank(row.path) != nil
            && nonblank(row.checksum) != nil
            && nonblank(row.destinationPath) != nil
    }

    private var isActiveCardTerminal: Bool {
        guard let state = activeCard?.localState else { return false }
        return state == .locallySafe || state == .issues || state == .cancelled
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

    private func nonblank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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

private extension Array where Element: Equatable {
    func firstSubsequenceIndex(of subsequence: [Element]) -> Int? {
        guard !subsequence.isEmpty, subsequence.count <= count else { return nil }
        for start in 0...(count - subsequence.count) {
            if Array(self[start..<(start + subsequence.count)]) == subsequence {
                return start
            }
        }
        return nil
    }
}

enum PhotographerJobViewModelError: LocalizedError, Equatable {
    case noActiveJob

    var errorDescription: String? {
        switch self {
        case .noActiveJob: return "Create or select a photographer job first."
        }
    }
}
