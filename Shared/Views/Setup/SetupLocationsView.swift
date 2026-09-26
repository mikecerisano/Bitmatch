import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// What the boxes can ask for. Picking opens the platform's picker (Mac:
/// the open panel; iOS: the Files picker); what was picked then goes through
/// `DestinationSelectionPolicy` and `BackupTargetPolicy`.
struct SetupLocationsActions {
    var pickSource: () -> Void
    var clearSource: () -> Void
    var pickBackups: () -> Void
    var removeBackup: (URL) -> Void
}

/// Dropping folders onto the boxes (the Mac). Each returns whether it took
/// the drop. iPad and iPhone pass none: a folder dragged from Files does not
/// bring lasting access with it, so picking is the one way in there.
struct SetupLocationsDrops {
    var source: ([NSItemProvider]) -> Bool
    var addBackups: ([NSItemProvider]) -> Bool
    /// Replaces the backup at the index (a drop onto an existing box).
    var replaceBackup: (Int, [NSItemProvider]) -> Bool
}

/// The source and backup boxes on Setup, one view for Mac, iPad and iPhone
/// (it replaces the Mac `HorizontalFlowView` and the iOS
/// `ProfessionalSourceCard` / `DestinationsFlowView`). It shows a
/// `SetupLocationsPresentation` and decides nothing itself.
///
/// The empty box that is the next step glows (`nextStepHighlight`) instead
/// of showing a banner. Every control is at least 44 pt tall and works
/// without hover. Selection is shown in the accent colour, never green:
/// green means verified.
struct SetupLocationsView: View {
    let presentation: SetupLocationsPresentation
    let actions: SetupLocationsActions
    var drops: SetupLocationsDrops? = nil

    @State private var isSourceTargeted = false
    @State private var isAddTargeted = false
    @State private var isAddMoreTargeted = false
    @State private var targetedBackup: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var pickerMinimumHeight: CGFloat {
        #if os(iOS)
        if horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
            return 240
        }
        #endif
        return 120
    }

    var body: some View {
        Group {
            if presentation.sideBySide {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        sourceBox
                            .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 34)
                            .accessibilityHidden(true)
                        backupsBox
                            .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
                    }
                    stacked
                }
            } else {
                stacked
            }
        }
        .padding(14)
        .background(
            SetupLocationsPanelBackground()
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSourceTargeted)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isAddTargeted)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: targetedBackup)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceBox
            backupsBox
        }
    }

    // MARK: Source

    private var sourceBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Source")
            if let source = presentation.source {
                selectedSource(source)
            } else {
                SetupLocationPicker(
                    symbol: "sdcard",
                    title: "Choose source…",
                    detail: drops == nil
                        ? "The card or folder to copy, from Files"
                        : "The card or folder to copy, or drag it here",
                    isTargeted: isSourceTargeted,
                    isHighlighted: presentation.highlightsSource,
                    isEnabled: presentation.canEdit,
                    action: actions.pickSource,
                    minimumHeight: pickerMinimumHeight
                )
                .accessibilityLabel("Choose source")
                .accessibilityHint("Opens a folder picker for the card or folder to copy")
            }
        }
        .fileDrop(isTargeted: $isSourceTargeted, enabled: presentation.canEdit, perform: drops?.source)
    }

    private func selectedSource(_ source: SetupLocationsPresentation.Source) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(source.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = source.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let camera = source.cameraName {
                    Label(camera, systemImage: "camera")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sourceAccessibilityLabel(source))
            if presentation.canEdit {
                removeButton(
                    label: "Clear source \(source.title)",
                    hint: "Removes the source from this transfer",
                    action: actions.clearSource
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SetupSelectedLocationBackground(isTargeted: isSourceTargeted)
        )
        .help(source.path)
    }

    private func sourceAccessibilityLabel(_ source: SetupLocationsPresentation.Source) -> String {
        ["Source: \(source.title)", source.detail, source.cameraName]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: Backups

    private var backupsBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Backups")
                Spacer(minLength: 0)
                if let count = presentation.backupCountTitle {
                    Text(count)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if presentation.backups.isEmpty {
                SetupLocationPicker(
                    symbol: "externaldrive.badge.plus",
                    title: "Add backup…",
                    detail: drops == nil
                        ? "A folder on each backup drive, from Files"
                        : "A folder on each backup drive, or drag them here",
                    isTargeted: isAddTargeted,
                    isHighlighted: presentation.highlightsBackups,
                    isEnabled: presentation.canEdit,
                    action: actions.pickBackups,
                    minimumHeight: pickerMinimumHeight
                )
                .accessibilityLabel("Add backup")
                .accessibilityHint("Opens a folder picker for one or more backups")
                .fileDrop(isTargeted: $isAddTargeted, enabled: presentation.canEdit, perform: drops?.addBackups)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(presentation.backups.enumerated()), id: \.element.id) { index, backup in
                        backupRow(backup, index: index)
                    }
                }
                if presentation.canEdit {
                    addMoreButton
                }
            }
        }
    }

    private func backupRow(_ backup: SetupLocationsPresentation.Backup, index: Int) -> some View {
        let isTargeted = targetedBackup == index
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(backup.title)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(backup.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let free = backup.freeSpace {
                    Text(free)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(["Backup: \(backup.title)", backup.freeSpace].compactMap { $0 }.joined(separator: ", "))
            if presentation.canEdit {
                removeButton(
                    label: "Remove backup \(backup.title)",
                    hint: "Removes \(backup.title) from the backups",
                    action: { actions.removeBackup(backup.url) }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
                )
        )
        .help(backup.path)
        .fileDrop(
            isTargeted: Binding(
                get: { targetedBackup == index },
                set: { targetedBackup = $0 ? index : (targetedBackup == index ? nil : targetedBackup) }
            ),
            enabled: presentation.canEdit,
            perform: replaceDrop(at: index)
        )
    }

    private func replaceDrop(at index: Int) -> (([NSItemProvider]) -> Bool)? {
        guard let drops else { return nil }
        return { providers in drops.replaceBackup(index, providers) }
    }

    private var addMoreButton: some View {
        Button(action: actions.pickBackups) {
            Label("Add backup…", systemImage: "plus.circle")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isAddMoreTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: isAddMoreTargeted ? 2 : 1, dash: isAddMoreTargeted ? [] : [5, 4])
                )
        )
        .accessibilityLabel("Add another backup")
        .accessibilityHint("Opens a folder picker for one or more backups")
        .fileDrop(isTargeted: $isAddMoreTargeted, enabled: presentation.canEdit, perform: drops?.addBackups)
    }

    // MARK: Parts

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func removeButton(label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

private extension View {
    /// Accepts dropped files and folders when there is a handler (the Mac)
    /// and editing is allowed; otherwise the view is not a drop target.
    @ViewBuilder
    func fileDrop(
        isTargeted: Binding<Bool>,
        enabled: Bool,
        perform: (([NSItemProvider]) -> Bool)?
    ) -> some View {
        if let perform, enabled {
            onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
                perform(providers)
            }
        } else {
            self
        }
    }
}

/// The shared empty location box; its entire area opens the picker.
struct SetupLocationPicker: View {
    let symbol: String
    let title: String
    let detail: String
    let isTargeted: Bool
    let isHighlighted: Bool
    let isEnabled: Bool
    let action: () -> Void
    var minimumHeight: CGFloat = 120

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 4])
                        )
                )
        )
        // A drop in progress already shows its own outline.
        .nextStepHighlight(isHighlighted && !isTargeted, cornerRadius: 10)
    }
}

struct SetupSelectedLocationBackground: View {
    var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isTargeted ? Color.accentColor : Color.accentColor.opacity(0.3), lineWidth: isTargeted ? 2 : 1)
            )
    }
}

struct SetupLocationsPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.primary.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}
