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

@MainActor
final class PhotographerJobViewModel: ObservableObject {
    typealias PreliminaryAnalyzer = ([FileEntry]) throws -> CardAnalysis
    typealias ConfirmedAnalyzer = ([ResultRow]) throws -> String

    @Published private(set) var jobs: [PhotographerJob] = []
    @Published var activeJob: PhotographerJob?
    @Published var selectedPhotographerID: UUID?
    @Published var cameraName = ""
    @Published private(set) var activeCardDraft: CardIngest?
    @Published private(set) var renderedRecipe: RenderedFolderRecipe?
    @Published private(set) var preliminaryAnalysis: CardAnalysis?
    @Published private(set) var duplicateWarning: DuplicateCardWarning?
    @Published private(set) var lastError: String?

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
            recipe: .wedding,
            requiredLocalCopyCount: 2,
            cardIngests: [],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        activeJob = job
        clearCardPreparation()
        persist(job)
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
        activeJob = job
        selectedPhotographerID = photographer.id
        self.cameraName = cameraName
        activeCardDraft = card
        renderedRecipe = rendered
        preliminaryAnalysis = analysis
        duplicateWarning = warning
        try persistThrowing(job)
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

    func completeIngest(results: [ResultRow]) throws {
        guard let requiredCount = activeJob?.requiredLocalCopyCount else { return }
        let groups = Dictionary(grouping: results, by: destinationIdentity)
        let verifiedGroups = groups.values.filter { rows in
            guard !rows.isEmpty,
                  Set(rows.map(\.path)).count == activeCard?.fileCount else { return false }
            return rows.allSatisfy(isVerified)
        }

        guard verifiedGroups.count >= requiredCount else {
            transitionActiveCard(to: .issues) { card in
                card.locallySafeAt = nil
                card.provenance.confirmedFingerprint = nil
            }
            return
        }

        let canonicalRows = uniqueRowsBySource(Array(verifiedGroups[0]))
        do {
            let fingerprint = try confirmedAnalyzer(canonicalRows)
            transitionActiveCard(to: .locallySafe) { card in
                card.locallySafeAt = self.now()
                card.provenance.confirmedFingerprint = fingerprint
            }
        } catch {
            transitionActiveCard(to: .issues) { card in
                card.locallySafeAt = nil
                card.provenance.confirmedFingerprint = nil
            }
            throw error
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

    private func loadJobs() {
        do {
            jobs = try store.jobs()
            lastError = nil
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
        guard var job = activeJob,
              let cardID = activeCardDraft?.id,
              let index = job.cardIngests.firstIndex(where: { $0.id == cardID }) else { return }
        guard job.cardIngests[index].localState != state else { return }

        job.cardIngests[index].localState = state
        mutate(&job.cardIngests[index])
        activeCardDraft = job.cardIngests[index]
        activeJob = job
        persist(job)
    }

    private func persist(_ job: PhotographerJob) {
        do {
            try persistThrowing(job)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistThrowing(_ job: PhotographerJob) throws {
        var updated = job
        updated.updatedAt = now()
        activeJob = updated
        try store.save(updated)
        if let index = jobs.firstIndex(where: { $0.id == updated.id }) {
            jobs[index] = updated
        } else {
            jobs.append(updated)
        }
        jobs.sort { $0.updatedAt > $1.updatedAt }
        lastError = nil
    }

    private func destinationIdentity(for row: ResultRow) -> String {
        if let destinationPath = row.destinationPath, !destinationPath.isEmpty {
            let pathComponents = URL(fileURLWithPath: destinationPath).pathComponents
            if let recipeComponents = renderedRecipe?.components,
               let recipeStart = pathComponents.firstSubsequenceIndex(of: recipeComponents) {
                let packageEnd = recipeStart + recipeComponents.count
                return NSString.path(withComponents: Array(pathComponents[..<packageEnd]))
            }
            return URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
        }
        if let destination = row.destination, !destination.isEmpty {
            return destination
        }
        return "missing-destination-\(row.id.uuidString)"
    }

    private func isVerified(_ row: ResultRow) -> Bool {
        row.isSuccessStatus && !(row.checksum?.isEmpty ?? true) && row.destinationPath != nil
    }

    private func uniqueRowsBySource(_ rows: [ResultRow]) -> [ResultRow] {
        var paths = Set<String>()
        return rows.sorted { $0.path < $1.path }.filter { paths.insert($0.path).inserted }
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
