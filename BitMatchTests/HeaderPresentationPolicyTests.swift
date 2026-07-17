import Testing
@testable import BitMatch

struct HeaderPresentationPolicyTests {
    @Test func fullModeStripOnlyAppearsWhenItHasRoom() {
        #expect(HeaderPresentationPolicy.presentation(for: 760) == .expanded)
        #expect(HeaderPresentationPolicy.presentation(for: 759) == .compact)
    }
}
