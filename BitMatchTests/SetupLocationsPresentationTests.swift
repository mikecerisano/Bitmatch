import Foundation
import Testing
@testable import BitMatch

/// The shared source and backup boxes (Mac, iPad and iPhone). Each test
/// names the one-line bug that should make it fail.
struct SetupLocationsPresentationTests {
    private let card = URL(fileURLWithPath: "/Volumes/CARD/DCIM", isDirectory: true)
    private let raid = URL(fileURLWithPath: "/Volumes/RAID_A/Shoot", isDirectory: true)

    private func make(
        source: URL? = nil,
        backups: [URL] = [],
        running: Bool = false,
        nextStep: TransferPlanPresentation.NextStep? = nil,
        layout: AdaptiveNavigationPresentation = .compact,
        analysing: Bool = false
    ) -> SetupLocationsPresentation {
        .make(
            sourceURL: source,
            sourceFileCount: 1_234,
            sourceBytes: 1_000_000_000,
            isAnalysingSource: analysing,
            cameraName: "",
            destinationURLs: backups,
            freeSpace: { _ in "2 TB" },
            isOperationInProgress: running,
            nextStep: nextStep,
            layout: layout
        )
    }

    /// Only the box that is the next step glows; a missing choice is never
    /// a banner.
    /// Plant: in `SetupLocationsPresentation.make`, set
    /// `highlightsBackups: destinationURLs.isEmpty` (ignore `nextStep`).
    @Test func onlyTheNextStepGlows() {
        let noSource = make(nextStep: .chooseSource)
        #expect(noSource.highlightsSource)
        #expect(!noSource.highlightsBackups)

        let noBackup = make(source: card, nextStep: .addBackup)
        #expect(!noBackup.highlightsSource)
        #expect(noBackup.highlightsBackups)
    }

    /// A running transfer locks the boxes on every platform.
    /// Plant: in `SetupLocationsPresentation.make`, set `canEdit: true`.
    @Test func runningTransferLocksEditing() {
        #expect(!make(source: card, backups: [raid], running: true).canEdit)
        #expect(make(source: card, backups: [raid]).canEdit)
    }

    /// Width decides the arrangement, not the device.
    /// Plant: in `SetupLocationsPresentation.make`, set
    /// `sideBySide: layout == .sidebar`.
    @Test func sideBySideFromToolbarWidth() {
        #expect(!make(layout: .compact).sideBySide)
        #expect(make(layout: .toolbar).sideBySide)
        #expect(make(layout: .sidebar).sideBySide)
    }

    /// Plant: in `SetupLocationsPresentation.sourceDetail`, drop the
    /// `if isAnalysing` line.
    @Test func sourceDetailWaitsForTheScan() {
        #expect(make(source: card, analysing: true).source?.detail == "Analyzing…")
        #expect(make(source: card).source?.detail == "1,234 files · 1 GB")
        // An empty camera name is no camera name.
        #expect(make(source: card).source?.cameraName == nil)
    }

    /// Plant: in `SetupLocationsPresentation.make`, pass
    /// `freeSpace: freeSpace(url)` (drop " available").
    @Test func backupsShowFreeSpace() {
        let presentation = make(backups: [raid])

        #expect(presentation.backups.map(\.title) == ["Shoot"])
        #expect(presentation.backups.first?.freeSpace == "2 TB available")
        #expect(presentation.backupCountTitle == "1 selected")
    }
}
