import Testing
@testable import BitMatch

struct CompletionEvidencePresentationTests {
    @Test func projectCompletionKeepsPreparedMediaVisible() {
        #expect(CompletionEvidencePresentation.shouldShowProjectMedia(
            hasDashboardJob: true,
            hasCardIngests: true
        ))
    }

    @Test func ordinaryCompletionDoesNotAddAnEmptyProjectPanel() {
        #expect(!CompletionEvidencePresentation.shouldShowProjectMedia(
            hasDashboardJob: false,
            hasCardIngests: false
        ))
    }
}
