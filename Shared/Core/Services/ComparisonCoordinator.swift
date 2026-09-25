// ComparisonCoordinator.swift - Extracted from SharedAppCoordinator for folder comparison
import Foundation

/// Handles folder comparison operations
@MainActor
final class ComparisonCoordinator {
    private let platformManager: PlatformManager
    private var cancellationRequested = false

    init(platformManager: PlatformManager) {
        self.platformManager = platformManager
    }

    func requestCancellation() {
        cancellationRequested = true
    }

    /// Observable for callers that publish results after the comparison returns,
    /// so a cancellation landing in the final checksum work cannot surface as
    /// a normal completion.
    var isCancellationRequested: Bool { cancellationRequested }

    private func throwIfCancelled() throws {
        if cancellationRequested { throw CancellationError() }
        try Task.checkCancellation()
    }

    /// Compare two folders and return stats
    func compareFolders(
        left: URL,
        right: URL,
        verificationMode: VerificationMode,
        onProgress: @escaping (OperationProgress) -> Void
    ) async throws -> CompareStats {
        cancellationRequested = false

        let didStartLeftScope = platformManager.fileSystem.startAccessing(url: left)
        let didStartRightScope = platformManager.fileSystem.startAccessing(url: right)
        defer {
            if didStartLeftScope {
                platformManager.fileSystem.stopAccessing(url: left)
            }
            if didStartRightScope {
                platformManager.fileSystem.stopAccessing(url: right)
            }
        }

        let sourceFiles = try await platformManager.fileSystem.getFileList(from: left)
        let destFiles = try await platformManager.fileSystem.getFileList(from: right)

        let sourceMap = try buildFileMap(files: sourceFiles, base: left)
        let destMap = try buildFileMap(files: destFiles, base: right)
        try throwIfCancelled()

        let sourceSet = Set(sourceMap.keys)
        let destSet = Set(destMap.keys)

        let onlyInSource = sourceSet.subtracting(destSet)
        let onlyInDest = destSet.subtracting(sourceSet).filter { !Self.isOffloadManifest($0) }
        let common = sourceSet.intersection(destSet)

        var mismatched: Set<String> = []
        // One plan for engine and screen: Paranoid is byte-by-byte plus SHA-256.
        let plan = CompareCheckPlan.make(for: verificationMode)
        let totalCommon = common.count
        var processedCommon = 0

        onProgress(OperationProgress(
            overallProgress: totalCommon == 0 ? 1.0 : 0.0,
            currentFile: nil,
            filesProcessed: 0,
            totalFiles: totalCommon,
            currentStage: .verifying,
            speed: nil,
            timeRemaining: nil
        ))

        for key in common {
            if cancellationRequested { throw CancellationError() }
            try Task.checkCancellation()
            guard let src = sourceMap[key], let dst = destMap[key] else { continue }

            if src.size != dst.size {
                mismatched.insert(key)
            } else if !(try await contentsMatch(src.url, dst.url, plan: plan)) {
                mismatched.insert(key)
            }
            try throwIfCancelled()

            processedCommon += 1
            let overall = totalCommon == 0 ? 1.0 : Double(processedCommon) / Double(totalCommon)
            onProgress(OperationProgress(
                overallProgress: overall,
                currentFile: key,
                filesProcessed: processedCommon,
                totalFiles: totalCommon,
                currentStage: .verifying,
                speed: nil,
                timeRemaining: nil
            ))
        }

        let matched = common.subtracting(mismatched)
        try throwIfCancelled()

        SharedLogger.info("Comparison complete", category: .transfer)
        SharedLogger.debug("Only in source: \(onlyInSource.count), Only in dest: \(onlyInDest.count), Common: \(matched.count), Mismatched: \(mismatched.count)", category: .transfer)

        return CompareStats(
            onlyInLeftCount: onlyInSource.count,
            onlyInRightCount: onlyInDest.count,
            commonCount: matched.count,
            mismatchedCount: mismatched.count,
            onlyInLeftPaths: onlyInSource.sorted(),
            onlyInRightPaths: onlyInDest.sorted(),
            mismatchedPaths: mismatched.sorted()
        )
    }

    // MARK: - Private Helpers

    /// Runs every check in `plan` and stops at the first one that fails.
    /// An empty plan (Quick) reads no contents and reports a match; the
    /// screen labels that "Sizes match, not verified".
    private func contentsMatch(_ source: URL, _ destination: URL, plan: CompareCheckPlan) async throws -> Bool {
        if plan.byteByByte {
            let identical = try await platformManager.checksum.performByteComparison(
                sourceURL: source,
                destinationURL: destination,
                progressCallback: nil
            )
            if !identical { return false }
            try throwIfCancelled()
        }
        for type in plan.checksums {
            let result = try await platformManager.checksum.verifyFileIntegrity(
                sourceURL: source,
                destinationURL: destination,
                type: type,
                progressCallback: nil
            )
            if !result.matches { return false }
        }
        return true
    }

    /// Finder writes these into any folder it displays, so a card and its offload
    /// differ as soon as someone browses one of them (GitHub issue #8). They are
    /// view state, not footage, and are ignored on both sides.
    static func isFinderMetadata(_ relativePath: String) -> Bool {
        let name = (relativePath as NSString).lastPathComponent
        return name == ".DS_Store" || name == "Icon\r" || name.hasPrefix("._")
    }

    /// Hash manifests an offload writes at the destination root: the ASC MHL
    /// `ascmhl/` history and legacy `.mhl` / `.mhl.md5` files (BitMatch 0.1.4
    /// paranoid transfers). Only ignored when the destination alone has them;
    /// one on the source that was not copied is still reported.
    static func isOffloadManifest(_ relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/")
        if parts.count > 1 { return parts[0].lowercased() == "ascmhl" }
        let name = relativePath.lowercased()
        return name.hasSuffix(".mhl") || name.hasSuffix(".mhl.md5")
    }

    private func buildFileMap(files: [URL], base: URL) throws -> [String: (url: URL, size: Int64)] {
        var map: [String: (url: URL, size: Int64)] = [:]
        map.reserveCapacity(files.count)
        let resolver = RelativePathResolver(base: base)
        for fileURL in files {
            let key = try resolver.resolve(fileURL)
            if Self.isFinderMetadata(key) { continue }
            let size = try platformManager.fileSystem.getFileSize(for: fileURL)
            map[key] = (fileURL, size)
        }
        return map
    }
}
