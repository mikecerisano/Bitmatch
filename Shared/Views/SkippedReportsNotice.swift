import SwiftUI

/// Wording for reports the Master Report scan found but could not list.
enum SkippedReportsPresentation {
    /// nil when nothing was skipped, so the notice is not shown.
    static func title(count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return "1 report couldn't be read"
        default: return "\(count) reports couldn't be read"
        }
    }

    static func reason(_ reason: ReportScanner.SkippedReport.Reason) -> String {
        switch reason {
        case .tooLarge: return "too large to read"
        case .unreadable: return "damaged or unreadable"
        }
    }

    static let footnote = "These transfers are not in this Master Report."

    /// Up to this many skipped reports show in full; a longer list scrolls
    /// so it cannot push the transfers off screen.
    static let maxRowsBeforeScrolling = 4

    static func scrolls(count: Int) -> Bool {
        count > maxRowsBeforeScrolling
    }
}

/// Shown on the Master Report screen on Mac, iPad and iPhone when the scan
/// skipped reports, naming each one. Shows nothing when none were skipped.
struct SkippedReportsNotice: View {
    let reports: [ReportScanner.SkippedReport]

    var body: some View {
        if let title = SkippedReportsPresentation.title(count: reports.count) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(report.displayName)
                            .font(.callout)
                            .textSelection(.enabled)
                        Text(SkippedReportsPresentation.reason(report.reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
                Text(SkippedReportsPresentation.footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
