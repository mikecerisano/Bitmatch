import Foundation
import Testing
@testable import BitMatch_iPad

/// Step 4.6 (P4), iOS side: iPad and iPhone write the same PDF, CSV and
/// JSON reports as the Mac (THESIS decision, 2026-09-25: "iPad and iPhone
/// get a PDF report too").
struct TransferOptionsPresentationIOSTests {
    // Plant: in `TransferOptionsPresentation.platformWritesPDF`, return `false`.
    @Test
    func iOSReportLabelPromisesThePDFTooNow() {
        #expect(TransferOptionsPresentation.platformWritesPDF)
        #expect(TransferOptionsPresentation.reportToggleTitle() == "Create PDF, CSV and JSON reports")
    }
}
