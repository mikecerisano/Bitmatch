import Testing
@testable import BitMatch

struct InterfaceLabNavigationTests {
    @Test func primaryJourneyMovesFromSetupToTransferToEvidence() {
        #expect(InterfaceLabRoute.next(after: .setup) == .transfer)
        #expect(InterfaceLabRoute.next(after: .transfer) == .evidence)
    }

    @Test func evidenceReturnsToSetupForTheNextJob() {
        #expect(InterfaceLabRoute.next(after: .evidence) == .setup)
    }

    @Test func theLabAlsoCoversComparisonAndReporting() {
        #expect(InterfaceLabRoute.allCases.contains(.compare))
        #expect(InterfaceLabRoute.allCases.contains(.report))
    }

    @Test func windowsRemainManuallyResizable() {
        #expect(WindowPresentationPolicy.allowsManualResizing)
    }
}
