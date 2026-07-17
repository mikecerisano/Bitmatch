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

    @Test func theLabExposesAnIssuesStateForRecoveryReview() {
        #expect(InterfaceLabRoute.allCases.contains(.issues))
    }

    @Test func compactWindowsUseANavigableMenuInsteadOfCrampedSegments() {
        #expect(InterfaceLabNavigationPolicy.presentation(for: 759) == .menu)
        #expect(InterfaceLabNavigationPolicy.presentation(for: 760) == .segmented)
    }

    @Test func windowsRemainManuallyResizable() {
        #expect(WindowPresentationPolicy.allowsManualResizing)
    }
}
