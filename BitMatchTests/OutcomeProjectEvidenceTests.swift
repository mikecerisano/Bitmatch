// OutcomeProjectEvidenceTests.swift
// Found by Swift 6 checking: the Mac passed its project dashboard as a
// trailing closure, which bound to the convenience init's `onNewTransfer`,
// so the completion screen never showed the dashboard or its off-site
// backup actions.
import SwiftUI
import Testing
@testable import BitMatch

@MainActor
struct OutcomeProjectEvidenceTests {
    /// Plant: give the `ProjectEvidence == EmptyView` init back an
    /// `onNewTransfer: @escaping () -> Void = {}` parameter.
    @Test func trailingClosureIsTheProjectEvidence() async throws {
        let fixture = try await SharedProjectFixture.make(prepareCard: false)
        let hasDashboard = fixture.coordinator.photographerJobViewModel.dashboardJob == nil
        // The Mac's shape: an `if` in the trailing closure.
        let screen = CoordinatorOutcomeScreen(coordinator: fixture.coordinator) {
            if hasDashboard {
                Text("dashboard")
            }
        }
        #expect(type(of: screen) != CoordinatorOutcomeScreen<EmptyView>.self)
        await fixture.cleanup()
    }
}
