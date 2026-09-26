import Foundation
import Testing
@testable import BitMatch
import BitMatchEngine

/// Master Report details built from the saved report settings (UI plan step 4.4).
@MainActor
struct ReportConfigurationTests {
    /// The Mac used to print the settings' notes as the technician's name.
    /// Plant: in `ReportConfiguration.make(from:productionNotes:)`, change
    /// `configuration.technician = ""` to `configuration.technician = prefs.notes`.
    @Test func technicianIsNotNotes() {
        var prefs = ReportPrefs()
        prefs.production = "Feature"
        prefs.clientName = "Client Co"
        prefs.company = "Post House"
        prefs.notes = "Card 3 was re-copied after a reader fault"

        let configuration = SharedReportGenerationService.ReportConfiguration.make(
            from: prefs, productionNotes: "Day 4"
        )

        #expect(configuration.technician != prefs.notes)
        #expect(configuration.technician.isEmpty)
        #expect(configuration.production == "Feature")
        #expect(configuration.client == "Client Co")
        #expect(configuration.company == "Post House")
        #expect(configuration.productionNotes == "Day 4")
    }
}
