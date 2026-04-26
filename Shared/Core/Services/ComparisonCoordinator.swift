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

    /// Compare two folders and return stats
    func compareFolders(
        left: URL,
        right: URL,
        verificationMode: VerificationMode,
        onProgress: @escaping (OperationProgress) -> Void
    ) async throws -> CompareStats {
        cancellationRequested = false

        let sourceFiles = try await platformManager.fileSystem.getFileList(from: left)
        let destFiles = try await platformManager.fileSystem.getFileList(from: right)

        let sourceMap = try buildFileMap(files: sourceFiles, base: left)
        let destMap = try buildFileMap(files: destFiles, base: right)

        let sourceSet = Set(sourceMap.keys)
        let destSet = Set(destMap.keys)

        let onlyInSource = sourceSet.subtracting(destSet)
        let onlyInDest = destSet.subtracting(sourceSet)
        let common = sourceSet.intersection(destSet)

        var mismatched: Set<String> = []
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
            } else if verificationMode == .quick {
                // size-only comparison already done
            } else if verificationMode == .paranoid {
                let matches = try await platformManager.checksum.performByteComparison(
                    sourceURL: src.url,
                    destinationURL: dst.url,
                    progressCallback: nil
                )
                if !matches { mismatched.insert(key) }
            } else if verificationMode.useChecksum {
                var allMatch = true
                let types = verificationMode == .thorough ? verificationMode.checksumTypes : [verificationMode.checksumTypes.first ?? .sha256]
                for type in types {
                    let result = try await platformManager.checksum.verifyFileIntegrity(
                        sourceURL: src.url,
                        destinationURL: dst.url,
                        type: type,
                        useCache: false,
                        progressCallback: nil
                    )
                    if !result.matches {
                        allMatch = false
                        break
                    }
                }
                if !allMatch { mismatched.insert(key) }
            }

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

        SharedLogger.info("Comparison complete", category: .transfer)
        SharedLogger.debug("Only in source: \(onlyInSource.count), Only in dest: \(onlyInDest.count), Common: \(matched.count), Mismatched: \(mismatched.count)", category: .transfer)

        return CompareStats(
            onlyInLeftCount: onlyInSource.count,
            onlyInRightCount: onlyInDest.count,
            commonCount: matched.count,
            mismatchedCount: mismatched.count
        )
    }

    // MARK: - Private Helpers

    private func relativePath(from base: URL, to fileURL: URL) -> String {
        let basePath = base.path
        let fullPath = fileURL.path
        if fullPath.hasPrefix(basePath + "/") {
            return String(fullPath.dropFirst(basePath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func buildFileMap(files: [URL], base: URL) throws -> [String: (url: URL, size: Int64)] {
        var map: [String: (url: URL, size: Int64)] = [:]
        map.reserveCapacity(files.count)
        for fileURL in files {
            let key = relativePath(from: base, to: fileURL)
            let size = try platformManager.fileSystem.getFileSize(for: fileURL)
            map[key] = (fileURL, size)
        }
        return map
    }
}
