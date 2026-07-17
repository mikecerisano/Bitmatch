import Testing
@testable import BitMatch

struct TransferOperationPresentationTests {
    @Test func copyingNamesTheCurrentPhase() {
        let presentation = TransferOperationPresentation.make(state: .copying, isPaused: false)

        #expect(presentation.title == "Copying")
        #expect(presentation.symbol == "arrow.right.circle.fill")
        #expect(presentation.controlTitle == "Pause")
    }

    @Test func pausedTransferMakesResumeThePrimaryControl() {
        let presentation = TransferOperationPresentation.make(state: .copying, isPaused: true)

        #expect(presentation.title == "Transfer paused")
        #expect(presentation.symbol == "pause.circle.fill")
        #expect(presentation.controlTitle == "Resume")
    }

    @Test func verificationNamesTheEvidencePhase() {
        let presentation = TransferOperationPresentation.make(state: .verifying, isPaused: false)

        #expect(presentation.title == "Verifying")
        #expect(presentation.symbol == "checkmark.shield.fill")
    }
}
