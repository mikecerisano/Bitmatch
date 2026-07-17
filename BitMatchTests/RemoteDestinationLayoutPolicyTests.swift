import Testing
@testable import BitMatch

struct RemoteDestinationLayoutPolicyTests {
    @Test func destinationFormStacksOnNarrowHosts() {
        #expect(RemoteDestinationLayoutPolicy.presentation(for: 519) == .stacked)
        #expect(RemoteDestinationLayoutPolicy.presentation(for: 520) == .twoColumn)
    }
}
