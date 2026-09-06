import Foundation

enum TransferPlanStatusTone: Equatable {
    case success
    case info
    case warning
    case error
}

struct TransferPlanStatusDisplay: Equatable {
    let title: String
    let detail: String
    let symbol: String
    let tone: TransferPlanStatusTone

    static func make(_ status: TransferPlanPresentation.Status) -> Self {
        switch status {
        case .ready:
            Self(title: "Ready to transfer", detail: "Source and backups are ready.", symbol: "checkmark.circle.fill", tone: .success)
        case .analyzing(let message):
            Self(title: "Analyzing", detail: message, symbol: "arrow.triangle.2.circlepath", tone: .info)
        case .warning(let warnings):
            Self(title: "Ready with warnings", detail: warnings.isEmpty ? "Review options before starting." : warnings.joined(separator: "\n"), symbol: "exclamationmark.triangle.fill", tone: .warning)
        case .blocked(let issues):
            Self(title: "Resolve before starting", detail: issues.isEmpty ? "Resolve the issue to continue." : issues.joined(separator: "\n"), symbol: "xmark.octagon.fill", tone: .error)
        case .incomplete(let message):
            Self(title: "Needs setup", detail: message, symbol: "info.circle.fill", tone: .warning)
        }
    }
}

/// A view-ready summary of transfer setup state.
///
/// This type deliberately contains no validation or transfer policy. Callers
/// provide the results of their existing validation and analysis work.
struct TransferPlanPresentation: Equatable {
    enum Status: Equatable {
        case incomplete(String)
        case analyzing(String)
        case ready
        case warning([String])
        case blocked([String])
    }

    let sourceTitle: String
    let sourceDetail: String
    let destinationTitles: [String]
    let destinationDetail: String
    let status: Status
    let optionSummary: [String]
    let actionTitle: String
    let canStart: Bool

    static func make(
        sourceURL: URL?,
        sourceInfo: FolderInfo?,
        destinationURLs: [URL],
        verificationMode: VerificationMode,
        cameraSettings: CameraLabelSettings,
        reportSettings: ReportPrefs,
        isAnalyzing: Bool,
        blockingIssues: [String],
        warnings: [String]
    ) -> Self {
        let status = status(
            sourceURL: sourceURL,
            destinationURLs: destinationURLs,
            isAnalyzing: isAnalyzing,
            blockingIssues: blockingIssues,
            warnings: warnings
        )

        return Self(
            sourceTitle: sourceURL?.lastPathComponent ?? "Choose source",
            sourceDetail: sourceDetail(for: sourceInfo, isAnalyzing: isAnalyzing),
            destinationTitles: destinationURLs.map(\.lastPathComponent),
            destinationDetail: destinationDetail(for: destinationURLs.count),
            status: status,
            optionSummary: optionSummary(
                verificationMode: verificationMode,
                cameraSettings: cameraSettings,
                reportSettings: reportSettings
            ),
            actionTitle: verificationMode == .quick
                ? "Start copy without checksum verification"
                : "Start verified copy",
            canStart: canStart(for: status)
        )
    }

    private static func status(
        sourceURL: URL?,
        destinationURLs: [URL],
        isAnalyzing: Bool,
        blockingIssues: [String],
        warnings: [String]
    ) -> Status {
        if !blockingIssues.isEmpty {
            return .blocked(blockingIssues)
        }
        guard sourceURL != nil else {
            return .incomplete("Choose a source folder")
        }
        guard !destinationURLs.isEmpty else {
            return .incomplete("Add at least one backup destination")
        }
        if isAnalyzing {
            return .analyzing("Analyzing source…")
        }
        if !warnings.isEmpty {
            return .warning(warnings)
        }
        return .ready
    }

    private static func sourceDetail(for sourceInfo: FolderInfo?, isAnalyzing: Bool) -> String {
        if isAnalyzing {
            return "Analyzing…"
        }
        guard let sourceInfo else {
            return "Analysis pending"
        }
        return "\(formattedCount(sourceInfo.fileCount)) files · \(formattedSize(sourceInfo.totalSize))"
    }

    private static func destinationDetail(for destinationCount: Int) -> String {
        guard destinationCount > 0 else {
            return "Add at least one backup"
        }
        let count = formattedCount(destinationCount)
        return destinationCount == 1 ? "\(count) backup selected" : "\(count) backups selected"
    }

    private static func optionSummary(
        verificationMode: VerificationMode,
        cameraSettings: CameraLabelSettings,
        reportSettings: ReportPrefs
    ) -> [String] {
        [
            "Verification: \(verificationMode.rawValue)",
            "Camera label: \(cameraSettings.label.isEmpty ? "Off" : cameraSettings.label)",
            reportSummary(for: reportSettings)
        ]
    }

    private static func reportSummary(for settings: ReportPrefs) -> String {
        guard settings.makeReport else {
            return "Reports: Off"
        }
        var formats: [String] = []
        if settings.generatePDF { formats.append("PDF") }
        if settings.generateCSV { formats.append("CSV") }
        return formats.isEmpty ? "Reports: On" : "Reports: \(formats.joined(separator: ", "))"
    }

    private static func canStart(for status: Status) -> Bool {
        switch status {
        case .ready, .warning:
            return true
        case .incomplete, .analyzing, .blocked:
            return false
        }
    }

    private static func formattedCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static func formattedSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
