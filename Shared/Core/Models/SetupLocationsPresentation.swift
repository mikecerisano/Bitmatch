import Foundation

/// The source and backup boxes on Setup, on every platform: what each box
/// shows, which empty box glows, and whether they can be changed. Built from
/// values, so Mac, iPad and iPhone show the same boxes for the same
/// selection; only how a folder is picked differs (`SetupLocationsPlatform`).
struct SetupLocationsPresentation: Equatable {
    struct Source: Equatable {
        let title: String
        let path: String
        /// "1,234 files · 12 GB", "Analyzing…", or nil before the scan.
        let detail: String?
        let cameraName: String?
    }

    struct Backup: Equatable, Identifiable {
        var id: URL { url }
        let url: URL
        let title: String
        let path: String
        /// "1.2 TB available", when the volume says.
        let freeSpace: String?
    }

    let source: Source?
    let backups: [Backup]
    /// False while a transfer runs: no clearing, removing, adding or drops.
    let canEdit: Bool
    /// The empty source box glows (the next step, never a banner).
    let highlightsSource: Bool
    /// The empty backups box glows.
    let highlightsBackups: Bool
    /// Source and backups side by side, from the Setup screen's own width
    /// (toolbar and sidebar widths); stacked when compact.
    let sideBySide: Bool

    var backupCountTitle: String? {
        switch backups.count {
        case 0: nil
        case 1: "1 selected"
        default: "\(backups.count) selected"
        }
    }

    static func make(
        sourceURL: URL?,
        sourceFileCount: Int?,
        sourceBytes: Int64?,
        isAnalysingSource: Bool,
        cameraName: String?,
        destinationURLs: [URL],
        freeSpace: (URL) -> String?,
        isOperationInProgress: Bool,
        nextStep: TransferPlanPresentation.NextStep?,
        layout: AdaptiveNavigationPresentation
    ) -> Self {
        let source = sourceURL.map { url in
            Source(
                title: url.lastPathComponent,
                path: url.path,
                detail: sourceDetail(fileCount: sourceFileCount, bytes: sourceBytes, isAnalysing: isAnalysingSource),
                cameraName: cameraName.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        return Self(
            source: source,
            backups: destinationURLs.map { url in
                Backup(
                    url: url,
                    title: url.lastPathComponent,
                    path: url.path,
                    freeSpace: freeSpace(url).map { "\($0) available" }
                )
            },
            canEdit: !isOperationInProgress,
            highlightsSource: sourceURL == nil && nextStep == .chooseSource,
            highlightsBackups: destinationURLs.isEmpty && nextStep == .addBackup,
            sideBySide: layout != .compact
        )
    }

    /// Free space on the volume holding `url`, formatted. Holds a security
    /// scope for the read (a Files-picker folder on iOS).
    static func formattedFreeSpace(for url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let available = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)
    }

    private static func sourceDetail(fileCount: Int?, bytes: Int64?, isAnalysing: Bool) -> String? {
        if isAnalysing { return "Analyzing…" }
        guard let fileCount, let bytes else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let count = formatter.string(from: NSNumber(value: fileCount)) ?? "\(fileCount)"
        let files = fileCount == 1 ? "1 file" : "\(count) files"
        return "\(files) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}
