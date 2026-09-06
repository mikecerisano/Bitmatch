import Foundation
import Testing
@testable import BitMatch

struct TransferPlanPresentationTests {
    private let sourceURL = URL(fileURLWithPath: "/Source/A001")
    private let destinationURL = URL(fileURLWithPath: "/Volumes/RAID_A")

    @Test
    func emptyPlanExplainsTheMissingSource() {
        let plan = TransferPlanPresentation.make(
            sourceURL: nil,
            sourceInfo: nil,
            destinationURLs: [],
            verificationMode: .standard,
            cameraSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(),
            isAnalyzing: false,
            blockingIssues: [],
            warnings: []
        )

        #expect(plan.sourceTitle == "Choose source")
        #expect(plan.destinationDetail == "Add at least one backup")
        #expect(plan.status == .incomplete("Choose a source folder"))
        #expect(!plan.canStart)
    }

    @Test
    func analyzingPlanDisablesStartUntilSourceAnalysisFinishes() {
        let plan = TransferPlanPresentation.make(
            sourceURL: sourceURL,
            sourceInfo: nil,
            destinationURLs: [destinationURL],
            verificationMode: .standard,
            cameraSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(),
            isAnalyzing: true,
            blockingIssues: [],
            warnings: []
        )

        #expect(plan.sourceTitle == "A001")
        #expect(plan.sourceDetail == "Analyzing…")
        #expect(plan.status == .analyzing("Analyzing source…"))
        #expect(!plan.canStart)
    }

    @Test
    func standardReadyPlanUsesVerifiedAction() {
        let plan = TransferPlanPresentation.make(
            sourceURL: sourceURL,
            sourceInfo: nil,
            destinationURLs: [destinationURL],
            verificationMode: .standard,
            cameraSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(),
            isAnalyzing: false,
            blockingIssues: [],
            warnings: []
        )

        #expect(plan.status == .ready)
        #expect(plan.actionTitle == "Start verified copy")
        #expect(plan.canStart)
    }

    @Test
    func warningPlanKeepsStartAvailableAndUsesQuickCopyAction() {
        let plan = TransferPlanPresentation.make(
            sourceURL: sourceURL,
            sourceInfo: nil,
            destinationURLs: [destinationURL],
            verificationMode: .quick,
            cameraSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(),
            isAnalyzing: false,
            blockingIssues: [],
            warnings: ["Quick mode does not verify checksums"]
        )

        #expect(plan.status == .warning(["Quick mode does not verify checksums"]))
        #expect(plan.actionTitle == "Start copy without checksum verification")
        #expect(plan.canStart)
    }

    @Test
    func blockedPlanTakesPrecedenceOverOtherStates() {
        let plan = TransferPlanPresentation.make(
            sourceURL: nil,
            sourceInfo: nil,
            destinationURLs: [],
            verificationMode: .standard,
            cameraSettings: CameraLabelSettings(),
            reportSettings: ReportPrefs(),
            isAnalyzing: true,
            blockingIssues: ["Destination is the source folder"],
            warnings: ["Quick mode does not verify checksums"]
        )

        #expect(plan.status == .blocked(["Destination is the source folder"]))
        #expect(!plan.canStart)
    }

    @Test
    func optionSummaryIncludesCameraAndReportLabels() {
        var cameraSettings = CameraLabelSettings()
        cameraSettings.label = "B Cam"
        var reportSettings = ReportPrefs()
        reportSettings.generateCSV = false

        let plan = TransferPlanPresentation.make(
            sourceURL: sourceURL,
            sourceInfo: folderInfo,
            destinationURLs: [destinationURL],
            verificationMode: .standard,
            cameraSettings: cameraSettings,
            reportSettings: reportSettings,
            isAnalyzing: false,
            blockingIssues: [],
            warnings: []
        )

        #expect(plan.sourceDetail == "1,234 files · 1 GB")
        #expect(plan.optionSummary.contains("Camera label: B Cam"))
        #expect(plan.optionSummary.contains("Reports: PDF"))
    }

    @Test
    func readyStatusUsesTheSameSafeLanguageOnEveryDevice() {
        let display = TransferPlanStatusDisplay.make(.ready)

        #expect(display.title == "Ready to transfer")
        #expect(display.detail == "Source and backups are ready.")
        #expect(display.symbol == "checkmark.circle.fill")
        #expect(display.tone == .success)
    }

    @Test
    func preflightDisplaysAllDestinationIssuesAndWarnings() {
        let issues = ["Backup A: Not enough space", "Backup B: Destination overlaps source"]
        let blocked = TransferPlanStatusDisplay.make(.blocked(issues))
        #expect(blocked.detail == issues.joined(separator: "\n"))
        #expect(blocked.tone == .error)

        let warnings = ["Quick mode checks size only", "Limited space on Backup B"]
        let warning = TransferPlanStatusDisplay.make(.warning(warnings))
        #expect(warning.detail == warnings.joined(separator: "\n"))
        #expect(warning.tone == .warning)
    }

    private var folderInfo: FolderInfo {
        FolderInfo(
            url: sourceURL,
            fileCount: 1_234,
            totalSize: 1_000_000_000,
            lastModified: .distantPast,
            isInternalDrive: false
        )
    }
}
