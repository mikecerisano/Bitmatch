// Views/CompareFoldersView.swift - Mac adapter over the shared CompareScreen
import SwiftUI
import AppKit

/// Builds the shared `ComparePresentation` from `AppCoordinator` and hands
/// picking, dropping and starting to the Mac. Readiness, progress and the
/// outcome are the same rules and screen as on iPad and iPhone.
struct CompareFoldersView: View {
    @ObservedObject var coordinator: AppCoordinator
    // Observed directly: AppCoordinator does not forward folder-info,
    // progress or compare-outcome changes.
    @ObservedObject private var fileSelection: FileSelectionViewModel
    @ObservedObject private var shared: SharedAppCoordinator
    @Binding var advancedExpanded: Bool

    init(coordinator: AppCoordinator, advancedExpanded: Binding<Bool>) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _fileSelection = ObservedObject(wrappedValue: coordinator.fileSelectionViewModel)
        _shared = ObservedObject(wrappedValue: coordinator.sharedCoordinator)
        _advancedExpanded = advancedExpanded
    }

    /// Also used by ⌘R, so the keyboard path obeys the same readiness rule.
    static func presentation(for coordinator: AppCoordinator) -> ComparePresentation {
        let files = coordinator.fileSelectionViewModel
        let shared = coordinator.sharedCoordinator
        return ComparePresentation.make(
            left: CompareFolderSlot.make(
                url: files.leftURL,
                infoURL: files.leftFolderInfo?.url,
                fileCount: files.leftFolderInfo?.fileCount,
                totalSize: files.leftFolderInfo?.totalSize,
                isFetching: files.isFetchingLeftInfo
            ),
            right: CompareFolderSlot.make(
                url: files.rightURL,
                infoURL: files.rightFolderInfo?.url,
                fileCount: files.rightFolderInfo?.fileCount,
                totalSize: files.rightFolderInfo?.totalSize,
                isFetching: files.isFetchingRightInfo
            ),
            mode: shared.verificationMode,
            isRunning: shared.isOperationInProgress,
            progress: shared.progress.map {
                CompareProgressPresentation(
                    fraction: $0.overallProgress,
                    filesProcessed: $0.filesProcessed,
                    totalFiles: $0.totalFiles,
                    currentFile: $0.currentFile
                )
            },
            stats: shared.lastCompareStats,
            end: shared.lastCompareEnd
        )
    }

    /// Starts only when the shared readiness rule says so.
    static func startIfReady(_ coordinator: AppCoordinator) {
        guard presentation(for: coordinator).readiness.canStart else { return }
        coordinator.switchMode(to: .compareFolders)
        coordinator.startOperation()
    }

    var body: some View {
        CompareScreen(
            presentation: Self.presentation(for: coordinator),
            verificationMode: $shared.verificationMode,
            advancedExpanded: $advancedExpanded,
            actions: CompareActions(
                pickLeft: { if let url = openFolderPanel() { fileSelection.leftURL = url } },
                pickRight: { if let url = openFolderPanel() { fileSelection.rightURL = url } },
                clearLeft: { fileSelection.leftURL = nil },
                clearRight: { fileSelection.rightURL = nil },
                dropLeft: { url in acceptDrop(url) { fileSelection.leftURL = $0 } },
                dropRight: { url in acceptDrop(url) { fileSelection.rightURL = $0 } },
                compare: { Self.startIfReady(coordinator) },
                cancel: { coordinator.cancelOperation() }
            )
        )
    }

    /// Folders only. Anything else is refused out loud, not silently ignored.
    private func acceptDrop(_ url: URL, assign: (URL) -> Void) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            assign(url)
        } else {
            NotificationCenter.default.post(
                name: .dropRejected,
                object: nil,
                userInfo: ["reason": "Drop a folder to compare, not a file."]
            )
        }
    }

    private func openFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
