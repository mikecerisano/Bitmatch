import Testing
@testable import BitMatch

struct AdaptiveWorkbenchLayoutTests {
    @Test func compactWindowUsesStackedPresentation() {
        #expect(AdaptiveWorkbenchLayout.presentation(for: 599) == .compact)
    }

    @Test func workbenchWindowUsesExpandedPresentation() {
        #expect(AdaptiveWorkbenchLayout.presentation(for: 600) == .expanded)
    }

    @Test func expandedWindowStaysExpandedAtLargeWidths() {
        #expect(AdaptiveWorkbenchLayout.presentation(for: 1_200) == .expanded)
    }

    @Test func compactDefaultWindowKeepsItsTransferRouteHorizontal() {
        // A 680-point window has approximately 612 points after the workbench's outer padding.
        #expect(AdaptiveWorkbenchLayout.presentation(for: 612) == .expanded)
    }
}
