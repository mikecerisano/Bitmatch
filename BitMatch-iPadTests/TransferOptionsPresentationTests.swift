import Foundation
import Testing
@testable import BitMatch_iPad

/// Step 4.6 (P4), iOS side: iPad and iPhone write CSV and JSON reports, no PDF.
struct TransferOptionsPresentationIOSTests {
    // Plant: in `TransferOptionsPresentation.reportFormatsDescription`, return
    // `"PDF, CSV and JSON"` unconditionally.
    @Test
    func iOSReportLabelDoesNotPromisePDF() {
        #expect(!TransferOptionsPresentation.platformWritesPDF)
        #expect(TransferOptionsPresentation.reportToggleTitle() == "Create CSV and JSON reports")
        #expect(!TransferOptionsPresentation.reportToggleTitle().contains("PDF"))
    }
}
