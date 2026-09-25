import SwiftUI
import Accessibility
import UniformTypeIdentifiers

/// What the outcome screen can ask its adapter to do. `retry` and `export`
/// are nil when the finished transfer has no journal record that allows them.
struct OutcomeActions {
    var newTransfer: () -> Void
    var retry: (() -> Void)?
    var export: ((_ asCSV: Bool) throws -> TransferHistoryDocument)?
}

extension OutcomeTone {
    var color: Color {
        switch self {
        case .verified: .green
        case .needsReview: .orange
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}

/// One completion screen for Mac, iPad and iPhone (UI plan step 4.7). It
/// shows a `TransferOutcomePresentation` and decides nothing itself. Layout
/// follows the screen's own width (`AdaptiveNavigationPolicy`): one column
/// when compact, backups in a grid at toolbar width, and two columns (verdict
/// and actions leading, backups and files trailing) at sidebar width.
///
/// It has no scroll view of its own: every shell already scrolls.
struct OutcomeScreen<ProjectEvidence: View>: View {
    let presentation: TransferOutcomePresentation
    let rows: [ResultRow]
    /// A real problem from the last action (for example Retry could not
    /// reach the original card). Nil otherwise: no banner for good news.
    let notice: String?
    let actions: OutcomeActions
    let isBusy: Bool
    private let projectEvidence: ProjectEvidence

    @State private var width: CGFloat = 0
    @State private var issuesOnly = false
    @State private var showsFiles = false
    @State private var exportDocument: TransferHistoryDocument?
    @State private var exportType = UTType.json
    @State private var showsExporter = false
    @State private var exportError: String?
    @AccessibilityFocusState private var verdictFocused: Bool

    init(
        presentation: TransferOutcomePresentation,
        rows: [ResultRow],
        notice: String? = nil,
        isBusy: Bool = false,
        actions: OutcomeActions,
        @ViewBuilder projectEvidence: () -> ProjectEvidence
    ) {
        self.presentation = presentation
        self.rows = rows
        self.notice = notice
        self.isBusy = isBusy
        self.actions = actions
        self.projectEvidence = projectEvidence()
    }

    private var layout: AdaptiveNavigationPresentation {
        AdaptiveNavigationPolicy.presentation(for: width)
    }

    var body: some View {
        Group {
            if layout == .sidebar {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        verdictHeader
                        issues
                        actionButtons
                        details
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 16) {
                        destinationList
                        projectEvidence
                        fileList
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    verdictHeader
                    issues
                    destinationList
                    actionButtons
                    projectEvidence
                    details
                    fileList
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onAppear {
            // Audit C3: the verdict of a long transfer is spoken, and focus
            // lands on it instead of being lost when the screen swaps.
            AccessibilityNotification.Announcement(presentation.announcement).post()
            verdictFocused = true
            // Audit M4: when something needs attention, open the evidence.
            if presentation.counts.needsAttention > 0 {
                showsFiles = true
                issuesOnly = true
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: exportType,
            defaultFilename: "BitMatch-transfer"
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
    }

    // MARK: Verdict

    private var verdictHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.verdict.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(presentation.tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.verdict.title)
                    .font(.title2.weight(.semibold))
                Text(presentation.verdict.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presentation.guidance)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let duration = presentation.durationLabel {
                    Text(duration)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($verdictFocused)
    }

    // MARK: Issues

    @ViewBuilder
    private var issues: some View {
        if !presentation.issueLines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(presentation.issueLines, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(presentation.tone == .failed ? Color.red : Color.orange)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(presentation.tone.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Backups

    @ViewBuilder
    private var destinationList: some View {
        if !presentation.destinations.isEmpty {
            let columns = layout == .toolbar
                ? [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
                : [GridItem(.flexible(), alignment: .topLeading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(presentation.destinations) { line in
                    OutcomeDestinationRow(line: line, cancelled: presentation.isCancelled)
                }
            }
        }
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let exportError {
                Label(exportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let stack = layout == .compact
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            stack {
                if presentation.primaryAction == .retry, let retry = actions.retry {
                    retryButton(retry, prominent: true)
                    newTransferButton(prominent: false)
                } else {
                    newTransferButton(prominent: true)
                    if let retry = actions.retry {
                        retryButton(retry, prominent: false)
                    }
                }
                if actions.export != nil {
                    exportMenu
                }
            }
            if let note = presentation.newTransferNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isBusy)
    }

    @ViewBuilder
    private func newTransferButton(prominent: Bool) -> some View {
        let button = Button(action: actions.newTransfer) {
            Label("New transfer", systemImage: "plus")
                .frame(maxWidth: layout == .compact ? .infinity : nil, minHeight: Self.minTarget)
        }
        .accessibilityHint(presentation.newTransferNote ?? "Clears this outcome.")
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func retryButton(_ retry: @escaping () -> Void, prominent: Bool) -> some View {
        let button = Button(action: retry) {
            Label("Retry transfer", systemImage: "arrow.clockwise")
                .frame(maxWidth: layout == .compact ? .infinity : nil, minHeight: Self.minTarget)
        }
        .accessibilityHint("Runs this transfer again from the same card to the same backups. The earlier attempt stays in history.")
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("JSON report") { export(asCSV: false) }
            Button("CSV results") { export(asCSV: true) }
        } label: {
            Label("Export report", systemImage: "square.and.arrow.up")
                .frame(maxWidth: layout == .compact ? .infinity : nil, minHeight: Self.minTarget)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize(horizontal: layout != .compact, vertical: false)
    }

    private func export(asCSV: Bool) {
        guard let makeDocument = actions.export else { return }
        do {
            exportDocument = try makeDocument(asCSV)
            exportType = asCSV ? .commaSeparatedText : .json
            exportError = nil
            showsExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Touch targets are 44 pt on iOS (AGENTS.md); the Mac uses its own
    /// regular control height.
    private static var minTarget: CGFloat {
        #if os(macOS)
        return 28
        #else
        return 44
        #endif
    }

    // MARK: Details

    private var details: some View {
        DisclosureGroup("Transfer details") {
            VStack(alignment: .leading, spacing: 6) {
                countLine("\(presentation.counts.verified) verified", systemImage: "checkmark.circle")
                if presentation.counts.copiedNotVerified > 0 {
                    countLine("\(presentation.counts.copiedNotVerified) copied, not verified", systemImage: "doc.on.doc")
                }
                if presentation.counts.needsAttention > 0 {
                    countLine("\(presentation.counts.needsAttention) need attention", systemImage: "exclamationmark.triangle")
                }
                if let bytes = presentation.bytesVerified {
                    countLine(
                        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) verified across all backups",
                        systemImage: "externaldrive"
                    )
                }
                if let mode = presentation.verificationModeLabel {
                    countLine(mode, systemImage: "checklist")
                }
            }
            .font(.callout)
            .padding(.top, 8)
        }
    }

    private func countLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(.secondary)
    }

    // MARK: Files

    private var fileList: some View {
        DisclosureGroup("File details", isExpanded: $showsFiles) {
            VStack(alignment: .leading, spacing: 10) {
                // A stable label (audit M12): VoiceOver says "Show issues only, on".
                Toggle("Show issues only", systemImage: "exclamationmark.triangle", isOn: $issuesOnly)
                    .toggleStyle(.button)
                    .frame(minHeight: Self.minTarget)

                let visible = ResultPresentation.visibleRows(
                    rows,
                    issuesOnly: issuesOnly,
                    limit: TransferOutcomePresentation.fileListLimit
                )
                if visible.isEmpty {
                    Text(presentation.emptyFileListText(issuesOnly: issuesOnly))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visible) { row in
                            OutcomeFileRow(row: row)
                        }
                    }
                }
                if let note = presentation.truncationNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }
}

extension OutcomeScreen where ProjectEvidence == EmptyView {
    init(
        presentation: TransferOutcomePresentation,
        rows: [ResultRow],
        notice: String? = nil,
        isBusy: Bool = false,
        actions: OutcomeActions
    ) {
        self.init(presentation: presentation, rows: rows, notice: notice, isBusy: isBusy, actions: actions) {
            EmptyView()
        }
    }
}

// MARK: - Rows

private struct OutcomeDestinationRow: View {
    let line: OutcomeDestinationLine
    let cancelled: Bool

    private var symbol: String {
        if cancelled { return "xmark.circle" }
        return line.needsAttention ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var tint: Color {
        if cancelled { return .secondary }
        return line.needsAttention ? .orange : .green
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.title)
                    .font(.headline)
                Text(line.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct OutcomeFileRow: View {
    let row: ResultRow

    var body: some View {
        let status = ResultStatusPresentation.make(status: row.status)
        let label = TransferOutcomePresentation.statusLabel(for: row.status)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.fileName)
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text([row.destination, label, row.formattedSize].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(row.isSuccessStatus ? Color.secondary : status.color)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
