import SwiftUI
import Accessibility

/// What the Compare screen can ask its platform adapter to do. The drop
/// actions are nil where drag and drop is not offered.
struct CompareActions {
    var pickLeft: () -> Void
    var pickRight: () -> Void
    var clearLeft: () -> Void
    var clearRight: () -> Void
    var dropLeft: ((URL) -> Void)?
    var dropRight: ((URL) -> Void)?
    var compare: () -> Void
    var cancel: () -> Void
}

/// One Compare screen for Mac, iPad and iPhone (UI plan step 4.2). It shows a
/// `ComparePresentation` and never decides anything itself: readiness, the
/// outcome and its wording all come from the model. Layout follows the
/// screen's own width (`AdaptiveNavigationPolicy`), not the device.
struct CompareScreen: View {
    let presentation: ComparePresentation
    @Binding var verificationMode: VerificationMode
    @Binding var advancedExpanded: Bool
    let actions: CompareActions

    @State private var width: CGFloat = 0

    private var layout: AdaptiveNavigationPresentation {
        AdaptiveNavigationPolicy.presentation(for: width)
    }

    var body: some View {
        Group {
            if layout == .sidebar, case .finished = presentation.phase {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        folders
                        controls
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    phaseContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    folders
                    controls
                    phaseContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onChange(of: presentation.verdict) { _, verdict in
            // Audit C3: a finished, failed or cancelled compare is announced.
            if let verdict {
                AccessibilityNotification.Announcement(verdict.announcement).post()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compare folders")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Check that a backup holds every file from the folder you trust, unchanged.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Folders

    private var folders: some View {
        let stack = layout == .compact
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return stack {
            CompareFolderSlotView(
                side: "Left folder",
                role: "The one you trust",
                slot: presentation.left,
                isEditable: presentation.allowsEditing,
                pick: actions.pickLeft,
                clear: actions.clearLeft,
                drop: actions.dropLeft
            )
            CompareFolderSlotView(
                side: "Right folder",
                role: "Checked against the left",
                slot: presentation.right,
                isEditable: presentation.allowsEditing,
                pick: actions.pickRight,
                clear: actions.clearRight,
                drop: actions.dropRight
            )
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if !presentation.isRunning {
            VStack(alignment: .leading, spacing: 12) {
                Label(presentation.verificationSummary,
                      systemImage: presentation.checkPlan.verifiesContents ? "shield.lefthalf.filled" : "exclamationmark.shield")
                    .font(.subheadline)
                    .foregroundStyle(presentation.checkPlan.verifiesContents ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(isExpanded: $advancedExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Verification", selection: $verificationMode) {
                            ForEach(VerificationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.radioGroup)
                        #else
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                        #endif
                        .disabled(!presentation.allowsEditing)

                        Text(CompareCheckPlan.make(for: verificationMode).summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("Advanced")
                        Spacer()
                        // Only a non-default choice is called out (§6).
                        if verificationMode != .standard {
                            Text("\(verificationMode.rawValue) mode")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }

                compareButton
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var compareButton: some View {
        let readiness = presentation.readiness
        let title: String = {
            if case .finished = presentation.phase { return "Compare again" }
            return "Compare folders"
        }()
        return VStack(alignment: layout == .compact ? .leading : .trailing, spacing: 8) {
            Button(action: actions.compare) {
                Label(title, systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: layout == .compact ? .infinity : nil, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!readiness.canStart)
            .accessibilityHint(readiness.message ?? "")

            if let message = readiness.message {
                let isBlocked: Bool = {
                    if case .blocked = readiness { return true }
                    return false
                }()
                Label(message, systemImage: isBlocked ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(isBlocked ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: layout == .compact ? .leading : .trailing)
    }

    // MARK: Phase

    @ViewBuilder
    private var phaseContent: some View {
        switch presentation.phase {
        case .setup:
            EmptyView()
        case .running(let progress):
            CompareProgressSection(progress: progress, cancel: actions.cancel)
        case .finished(let outcome):
            switch outcome {
            case .match, .sizesMatchNotVerified, .differ:
                if let stats = presentation.stats {
                    CompareResultsView(
                        stats: stats,
                        leftName: presentation.leftName,
                        rightName: presentation.rightName,
                        verificationMode: presentation.mode
                    )
                }
            case .cancelled, .failed:
                if let verdict = presentation.verdict {
                    CompareVerdictHeader(verdict: verdict)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Folder slot

private struct CompareFolderSlotView: View {
    let side: String
    let role: String
    let slot: CompareFolderSlot
    let isEditable: Bool
    let pick: () -> Void
    let clear: () -> Void
    let drop: ((URL) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(side)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let name = slot.name {
                VStack(alignment: .leading, spacing: 4) {
                    Label(name, systemImage: "folder.fill")
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if let path = slot.path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    details
                }
                HStack(spacing: 8) {
                    Button("Change…", action: pick)
                        .accessibilityLabel("Change \(side.lowercased())")
                    Button("Clear", role: .destructive, action: clear)
                        .accessibilityLabel("Clear \(side.lowercased())")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!isEditable)
            } else {
                Button(action: pick) {
                    Label("Choose folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!isEditable)
                .accessibilityLabel("Choose \(side.lowercased())")
                if drop != nil {
                    Text("Or drop a folder here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(isTargeted ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
        )
        .modifier(FolderDropTarget(drop: isEditable ? drop : nil, isTargeted: $isTargeted))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var details: some View {
        if slot.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading folder…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else if slot.detailsUnavailable {
            Text("Folder details unavailable. Compare will still read it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let count = slot.fileCountText, let size = slot.sizeText {
            Text("\(count) · \(size)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Accepts one dropped folder when `drop` is set. The adapter decides whether
/// the item is a folder and explains a rejection; nothing is silently ignored.
private struct FolderDropTarget: ViewModifier {
    let drop: ((URL) -> Void)?
    @Binding var isTargeted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let drop {
            content.dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                drop(url)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        } else {
            content
        }
    }
}

// MARK: - Progress

private struct CompareProgressSection: View {
    let progress: CompareProgressPresentation
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comparing…")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ProgressView(value: min(max(progress.fraction, 0), 1)) {
                Text(progress.countText)
                    .font(.subheadline)
            } currentValueLabel: {
                Text(progress.percentText)
                    .font(.caption)
            }
            .accessibilityLabel("Compare progress")
            .accessibilityValue("\(progress.percentText), \(progress.countText)")
            if let file = progress.currentFile {
                Text(file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Cancel compare", role: .cancel, action: cancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Verdict

extension CompareTone {
    var color: Color {
        switch self {
        case .verified: .green
        case .notVerified: .orange
        case .differ, .failed: .red
        case .cancelled: .secondary
        }
    }
}

/// The outcome headline: a symbol, a title and a sentence, so the verdict
/// never depends on colour alone (audit M6).
struct CompareVerdictHeader: View {
    let verdict: CompareVerdictPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(verdict.title, systemImage: verdict.symbol)
                .font(.headline)
                .foregroundStyle(verdict.tone.color)
            Text(verdict.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
