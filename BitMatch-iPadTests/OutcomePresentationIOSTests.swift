import Foundation
import Testing
@testable import BitMatch_iPad

/// Step 4.7, iOS side: iPad and iPhone build the outcome through the same
/// `TransferOutcomePresentation.make` as the Mac, so a cancelled transfer
/// reads as cancelled here too.
struct OutcomePresentationIOSTests {
    // Plant: in `OutcomeTone.make`, derive the tone from the verdict symbol, as
    // the old Mac `completionTint` did (a cancelled run then reads `.failed`).
    @Test
    func cancelledToneIsCancelled() {
        let backup = URL(fileURLWithPath: "/private/var/mobile/Backup", isDirectory: true)
        let rows = [
            ResultRow(path: "/Card/A001.mov", status: ResultOutcome.copiedUnverified.statusText, size: 10,
                      checksum: nil, destination: "Backup", destinationPath: backup.appendingPathComponent("A001.mov").path)
        ]
        let outcome = TransferOutcomePresentation.make(
            state: .cancelled,
            rows: rows,
            destinations: [backup],
            hasErrors: true,
            hasCriticalErrors: false,
            errorCount: 0,
            warningCount: 1,
            duration: 30,
            verificationMode: .standard,
            canRetry: true,
            canExport: true
        )
        #expect(outcome.tone == .cancelled)
        #expect(outcome.verdict.title == "Transfer cancelled")
        #expect(outcome.issueLines.isEmpty)
        #expect(outcome.durationLabel == "Stopped after 30s")
        #expect(outcome.primaryAction == .newTransfer)
    }
}
