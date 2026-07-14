import Foundation
import Testing
@testable import BitMatch

struct PhotographerJobPresentationTests {
    private let eventDate = Date(timeIntervalSince1970: 100)

    @Test func validWeddingSetupHasCompactCollapsedSummary() {
        let presentation = setup()

        #expect(presentation.presetTitle == "Wedding")
        #expect(presentation.collapsedSummary == "Smith Wedding · Mike · Sony A7 IV · Card 001")
        #expect(presentation.blockers.isEmpty)
    }

    @Test func disabledLayerIsOmittedFromLivePreview() {
        var recipe = FolderRecipe.wedding
        recipe.layers[2].isEnabled = false

        let presentation = setup(recipe: recipe)

        #expect(presentation.pathPreview == "1970-01-01_Smith-Wedding/Originals/Sony-A7-IV/Card-001")
        #expect(!presentation.pathPreview.contains("/Mike/"))
    }

    @Test func missingPhotographerAndCameraAreSetupBlockers() {
        let presentation = setup(photographerName: "  ", cameraName: "")

        #expect(presentation.blockers == ["Enter a photographer", "Enter a camera"])
        #expect(!presentation.canSetUpCard)
    }

    @Test func missingClientAndJobAreSetupBlockers() {
        let presentation = PhotographerJobSetupPresentation.make(
            clientName: "",
            jobName: " ",
            eventDate: eventDate,
            photographerName: "Mike",
            cameraName: "Sony A7 IV",
            cardNumber: 1,
            recipe: .wedding,
            duplicateWarningText: nil
        )

        #expect(presentation.blockers == ["Enter a client", "Enter a job name"])
    }

    @Test func duplicateWarningUsesPlainCopyAndEarlierIngestLinkLabel() {
        let presentation = setup(
            duplicateWarningText: "This card appears to have already been ingested for Smith Wedding."
        )

        #expect(presentation.duplicateWarningText == "This card appears to have already been ingested for Smith Wedding.")
        #expect(presentation.duplicateLinkTitle == "Show earlier ingest")
    }

    @Test func everyLocalStateUsesExplicitStatusCopyAndSymbol() {
        let expected: [(PhotographerLocalState, String, String)] = [
            (.notStarted, "Not Started", "circle"),
            (.copying, "Copying", "doc.on.doc.fill"),
            (.verifying, "Verifying", "checkmark.shield"),
            (.locallySafe, "Locally Safe", "checkmark.shield.fill"),
            (.issues, "Issues", "exclamationmark.triangle.fill"),
            (.cancelled, "Cancelled", "xmark.circle.fill")
        ]

        for (state, title, symbol) in expected {
            let row = PhotographerCardRowPresentation.make(
                card: card(number: 1, state: state),
                verifiedDestinationCount: state == .locallySafe ? 2 : 0
            )
            #expect(row.statusTitle == title)
            #expect(row.statusSymbol == symbol)
        }
    }

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

    @Test func sessionShowsRequiredAndVerifiedCopyCounts() {
        var completed = card(number: 1, state: .locallySafe)
        completed.verifiedDestinationCount = 3
        let job = makeJob(cards: [completed], requiredCopies: 2)

        let session = PhotographerSessionPresentation.make(job: job)

        #expect(session.requiredCopyTitle == "2 verified local copies required")
        #expect(session.rows.first?.verifiedCopyTitle == "3 of 2 verified")
    }

    @Test func startPresentationOwnsEveryPhotographyBlockerString() {
        let cases: [(PhotographerStartContext, String)] = [
            (.init(preflightReady: false, isPreparing: false, activeCardState: .notStarted, sourceMatches: true, setupMatches: true, destinationCount: 2, requiredDestinationCount: 2), "Resolve transfer preflight issues"),
            (.init(preflightReady: true, isPreparing: true, activeCardState: .notStarted, sourceMatches: true, setupMatches: true, destinationCount: 2, requiredDestinationCount: 2), "Card setup is still preparing"),
            (.init(preflightReady: true, isPreparing: false, activeCardState: nil, sourceMatches: false, setupMatches: false, destinationCount: 2, requiredDestinationCount: 2), "Set up this card before starting"),
            (.init(preflightReady: true, isPreparing: false, activeCardState: .locallySafe, sourceMatches: true, setupMatches: true, destinationCount: 2, requiredDestinationCount: 2), "Set up the next card before starting"),
            (.init(preflightReady: true, isPreparing: false, activeCardState: .notStarted, sourceMatches: false, setupMatches: true, destinationCount: 2, requiredDestinationCount: 2), "Source changed; set up the card again"),
            (.init(preflightReady: true, isPreparing: false, activeCardState: .notStarted, sourceMatches: true, setupMatches: false, destinationCount: 2, requiredDestinationCount: 2), "Setup changed; set up the card again"),
            (.init(preflightReady: true, isPreparing: false, activeCardState: .notStarted, sourceMatches: true, setupMatches: true, destinationCount: 1, requiredDestinationCount: 2), "Add 1 more destination for this 2-copy job")
        ]

        for (context, expected) in cases {
            let presentation = PhotographerStartPresentation.make(context: context)
            #expect(presentation.blocker == expected)
            #expect(!presentation.canStart)
        }
    }

    @Test func cardIngestDecodesLegacyPayloadWithZeroVerifiedDestinations() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000202","provenance":{"photographerID":"00000000-0000-0000-0000-000000000201","photographerName":"Mike","cameraName":"Sony","cardNumber":1},"sourceDisplayName":"CARD1","renderedRelativePath":"Card-001","localState":"locallySafe","fileCount":1,"totalBytes":100}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CardIngest.self, from: legacy)

        #expect(decoded.verifiedDestinationCount == 0)
    }

    @Test func sessionSortsActiveThenNewestCards() {
        var oldSafe = card(number: 1, state: .locallySafe)
        oldSafe.startedAt = Date(timeIntervalSince1970: 100)
        var newSafe = card(number: 2, state: .locallySafe)
        newSafe.startedAt = Date(timeIntervalSince1970: 300)
        let pending = card(number: 3, state: .notStarted)

        let session = PhotographerSessionPresentation.make(
            job: makeJob(cards: [oldSafe, pending, newSafe], requiredCopies: 2)
        )

        #expect(session.rows.map(\.cardTitle) == ["Card 003", "Card 002", "Card 001"])
    }

    private func setup(
        photographerName: String = "Mike",
        cameraName: String = "Sony A7 IV",
        recipe: FolderRecipe = .wedding,
        duplicateWarningText: String? = nil
    ) -> PhotographerJobSetupPresentation {
        PhotographerJobSetupPresentation.make(
            clientName: "Smith",
            jobName: "Smith Wedding",
            eventDate: eventDate,
            photographerName: photographerName,
            cameraName: cameraName,
            cardNumber: 1,
            recipe: recipe,
            duplicateWarningText: duplicateWarningText
        )
    }

    private func card(number: Int, state: PhotographerLocalState) -> CardIngest {
        CardIngest(
            id: UUID(),
            provenance: CardProvenance(
                photographerID: UUID(),
                photographerName: "Mike",
                cameraName: "Sony A7 IV",
                cardNumber: number,
                preliminaryFingerprint: "preliminary-\(number)",
                confirmedFingerprint: state == .locallySafe ? "confirmed-\(number)" : nil
            ),
            sourceDisplayName: "CARD\(number)",
            renderedRelativePath: "Smith-Wedding/Originals/Mike/Sony-A7-IV/Card-\(number)",
            localState: state,
            startedAt: nil,
            locallySafeAt: nil,
            fileCount: number,
            totalBytes: Int64(number * 100)
        )
    }

    private func makeJob(cards: [CardIngest], requiredCopies: Int) -> PhotographerJob {
        PhotographerJob(
            id: UUID(),
            eventDate: eventDate,
            clientName: "Smith",
            jobName: "Smith Wedding",
            eventType: .wedding,
            photographers: [],
            recipe: .wedding,
            requiredLocalCopyCount: requiredCopies,
            cardIngests: cards,
            createdAt: eventDate,
            updatedAt: eventDate
        )
    }
}
