import Foundation

struct PhotographerJobSetupPresentation: Equatable, Sendable {
    let presetTitle: String
    let collapsedSummary: String
    let pathPreview: String
    let blockers: [String]
    let duplicateWarningText: String?
    let duplicateLinkTitle: String?

    var canSetUpCard: Bool { blockers.isEmpty }

    static func make(
        clientName: String,
        jobName: String,
        eventDate: Date,
        photographerName: String,
        cameraName: String,
        cardNumber: Int,
        recipe: FolderRecipe,
        duplicateWarningText: String?,
        hasSource: Bool = true,
        isPreparing: Bool = false
    ) -> Self {
        let cleanClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanJob = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhotographer = photographerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCamera = cameraName.trimmingCharacters(in: .whitespacesAndNewlines)
        var blockers: [String] = []
        if cleanClient.isEmpty { blockers.append("Enter a client") }
        if cleanJob.isEmpty { blockers.append("Enter a job name") }
        if cleanPhotographer.isEmpty { blockers.append("Enter a photographer") }
        if cleanCamera.isEmpty { blockers.append("Enter a camera") }
        if !hasSource { blockers.append("Choose a source card") }
        if isPreparing { blockers.append("Card setup is still preparing") }

        let rendered = try? FolderRecipeRenderer.render(
            recipe,
            context: FolderRecipeContext(
                eventDate: eventDate,
                jobName: cleanJob,
                photographer: cleanPhotographer,
                camera: cleanCamera,
                cardNumber: cardNumber
            )
        )

        return Self(
            presetTitle: recipe.name,
            collapsedSummary: [
                cleanJob,
                cleanPhotographer,
                cleanCamera,
                String(format: "Card %03d", cardNumber)
            ].filter { !$0.isEmpty }.joined(separator: " · "),
            pathPreview: rendered?.relativePath ?? "Complete setup to preview the package path",
            blockers: blockers,
            duplicateWarningText: duplicateWarningText,
            duplicateLinkTitle: duplicateWarningText == nil ? nil : "Show earlier ingest"
        )
    }
}

struct PhotographerStartContext: Equatable, Sendable {
    let preflightReady: Bool
    let isPreparing: Bool
    let activeCardState: PhotographerLocalState?
    let sourceMatches: Bool
    let setupMatches: Bool
    let destinationCount: Int
    let requiredDestinationCount: Int
    let verificationMode: VerificationMode
}

struct PhotographerStartPresentation: Equatable, Sendable {
    let blocker: String?
    var canStart: Bool { blocker == nil }

    static func make(context: PhotographerStartContext) -> Self {
        let blocker: String?
        if !context.preflightReady {
            blocker = "Resolve transfer preflight issues"
        } else if context.isPreparing {
            blocker = "Card setup is still preparing"
        } else if context.activeCardState == nil {
            blocker = "Set up this card before starting"
        } else if context.activeCardState != .notStarted {
            blocker = "Set up the next card before starting"
        } else if context.verificationMode == .quick {
            blocker = "Photographer ingests require Standard, Thorough, or Paranoid verification; Quick mode cannot establish locally safe evidence."
        } else if !context.sourceMatches {
            blocker = "Source changed; set up the card again"
        } else if !context.setupMatches {
            blocker = "Setup changed; set up the card again"
        } else if context.destinationCount < context.requiredDestinationCount {
            let missing = context.requiredDestinationCount - context.destinationCount
            let noun = missing == 1 ? "destination" : "destinations"
            blocker = "Add \(missing) more \(noun) for this \(context.requiredDestinationCount)-copy job"
        } else {
            blocker = nil
        }
        return Self(blocker: blocker)
    }

    static func insufficientDestinationError(requiredCount: Int) -> String {
        "This job requires \(requiredCount) verified local destinations."
    }
}

struct PhotographerCardRowPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let photographerName: String
    let cameraName: String
    let cardTitle: String
    let fileCountTitle: String
    let byteCountTitle: String
    let renderedPath: String
    let statusTitle: String
    let statusSymbol: String
    let verifiedDestinationCount: Int
    let verifiedCopyTitle: String

    static func make(
        card: CardIngest,
        verifiedDestinationCount: Int,
        requiredCopyCount: Int = 0
    ) -> Self {
        let status = status(for: card.localState)
        let copyTitle = requiredCopyCount > 0
            ? "\(verifiedDestinationCount) of \(requiredCopyCount) verified"
            : "\(verifiedDestinationCount) verified destinations"
        return Self(
            id: card.id,
            photographerName: card.provenance.photographerName,
            cameraName: card.provenance.cameraName,
            cardTitle: String(format: "Card %03d", card.provenance.cardNumber),
            fileCountTitle: formattedFileCount(card.fileCount),
            byteCountTitle: ByteCountFormatter.string(fromByteCount: card.totalBytes, countStyle: .file),
            renderedPath: card.renderedRelativePath,
            statusTitle: status.title,
            statusSymbol: status.symbol,
            verifiedDestinationCount: verifiedDestinationCount,
            verifiedCopyTitle: copyTitle
        )
    }

    private static func status(for state: PhotographerLocalState) -> (title: String, symbol: String) {
        switch state {
        case .notStarted: return ("Not Started", "circle")
        case .copying: return ("Copying", "doc.on.doc.fill")
        case .verifying: return ("Verifying", "checkmark.shield")
        case .locallySafe: return ("Locally Safe", "checkmark.shield.fill")
        case .issues: return ("Issues", "exclamationmark.triangle.fill")
        case .cancelled: return ("Cancelled", "xmark.circle.fill")
        }
    }

    private static func formattedFileCount(_ count: Int) -> String {
        let formatted = count.formatted(.number)
        return count == 1 ? "\(formatted) file" : "\(formatted) files"
    }
}

struct PhotographerSessionPresentation: Equatable, Sendable {
    let title: String
    let requiredCopyTitle: String
    let rows: [PhotographerCardRowPresentation]

    static func make(job: PhotographerJob) -> Self {
        let sortedCards = job.cardIngests.sorted { lhs, rhs in
            let lhsPending = lhs.localState == .notStarted
            let rhsPending = rhs.localState == .notStarted
            if lhsPending != rhsPending { return lhsPending }
            let lhsDate = lhs.startedAt ?? .distantPast
            let rhsDate = rhs.startedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.provenance.cardNumber > rhs.provenance.cardNumber
        }
        let required = job.requiredLocalCopyCount
        let rows = sortedCards.map { card in
            return PhotographerCardRowPresentation.make(
                card: card,
                verifiedDestinationCount: card.verifiedDestinationCount,
                requiredCopyCount: required
            )
        }
        let copyNoun = required == 1 ? "copy" : "copies"
        return Self(
            title: "\(job.jobName) session",
            requiredCopyTitle: "\(required) verified local \(copyNoun) required",
            rows: rows
        )
    }
}
