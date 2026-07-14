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
    typealias PreliminaryAnalyzer = ([FileEntry]) throws -> CardAnalysis
    typealias ConfirmedAnalyzer = ([ResultRow]) throws -> String

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

    var activeCard: CardIngest? {
        guard let id = activeCardDraft?.id else { return nil }
        return activeJob?.cardIngests.first { $0.id == id }
    }

    private let store: any PhotographerJobStore
    private let now: () -> Date
    private let preliminaryAnalyzer: PreliminaryAnalyzer
    private let confirmedAnalyzer: ConfirmedAnalyzer

    init(
        store: any PhotographerJobStore,
        now: @escaping () -> Date = Date.init,
        preliminaryAnalyzer: @escaping PreliminaryAnalyzer = PhotographerCardAnalyzer.preliminaryAnalysis,
        confirmedAnalyzer: @escaping ConfirmedAnalyzer = PhotographerCardAnalyzer.confirmedFingerprint
    ) {
        self.store = store
        self.now = now
        self.preliminaryAnalyzer = preliminaryAnalyzer
        self.confirmedAnalyzer = confirmedAnalyzer
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

    func beginIngest(destinationCount: Int) {
        guard let job = activeJob else { return }
        let destinationError = destinationCount < job.requiredLocalCopyCount
            ? "This job requires " + String(job.requiredLocalCopyCount) + " verified local destinations."
            : nil
        transitionActiveCard(to: .copying) { card in
            if card.startedAt == nil { card.startedAt = self.now() }
            card.locallySafeAt = nil
        }
        lastError = destinationError
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
    }

    func moveDraftLayer(_ id: UUID, direction: FolderLayerMoveDirection) {
        guard let index = draftRecipe.layers.firstIndex(where: { $0.id == id }) else { return }
        let destination = direction == .up ? index - 1 : index + 1
        guard draftRecipe.layers.indices.contains(destination) else { return }
        draftRecipe.layers.swapAt(index, destination)
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
    }

    func focusCardIngest(id: UUID) {
        focusedCardIngestID = id
    }

    private func loadJobs() {
        do {
            jobs = try store.jobs()
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
        lastError = nil
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
