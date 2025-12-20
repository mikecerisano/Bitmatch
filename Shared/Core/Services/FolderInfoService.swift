// FolderInfoService.swift - Centralized folder info scanning and caching
import Foundation
import Combine

/// Service that handles folder info scanning with caching and loading state tracking
@MainActor
final class FolderInfoService: ObservableObject {
    static let shared = FolderInfoService()

    // MARK: - Published State
    @Published private(set) var sourceFolderInfo: EnhancedFolderInfo?
    @Published private(set) var leftFolderInfo: EnhancedFolderInfo?
    @Published private(set) var rightFolderInfo: EnhancedFolderInfo?
    @Published private(set) var destinationFolderInfos: [URL: EnhancedFolderInfo] = [:]
    @Published private(set) var folderInfoLoadingState: [URL: Bool] = [:]

    // Track which URLs are currently assigned to which role
    private var sourceURL: URL?
    private var leftURL: URL?
    private var rightURL: URL?
    private var destinationURLs: [URL] = []

    // MARK: - Public API

    /// Update source folder info when source URL changes
    func updateSource(_ url: URL?) async {
        sourceURL = url
        if let url = url {
            folderInfoLoadingState[url] = true
            let info = await getEnhancedFolderInfo(for: url)
            sourceFolderInfo = info
            folderInfoLoadingState[url] = false
        } else {
            sourceFolderInfo = nil
        }
    }

    /// Update left folder info (for comparison mode)
    func updateLeft(_ url: URL?) async {
        leftURL = url
        if let url = url {
            folderInfoLoadingState[url] = true
            let info = await getEnhancedFolderInfo(for: url)
            leftFolderInfo = info
            folderInfoLoadingState[url] = false
        } else {
            leftFolderInfo = nil
        }
    }

    /// Update right folder info (for comparison mode)
    func updateRight(_ url: URL?) async {
        rightURL = url
        if let url = url {
            folderInfoLoadingState[url] = true
            let info = await getEnhancedFolderInfo(for: url)
            rightFolderInfo = info
            folderInfoLoadingState[url] = false
        } else {
            rightFolderInfo = nil
        }
    }

    /// Update destination folder infos when destination list changes
    func updateDestinations(_ urls: [URL]) async {
        destinationURLs = urls

        // Find new URLs that need scanning
        let newURLs = urls.filter { destinationFolderInfos[$0] == nil }

        if !newURLs.isEmpty {
            for url in newURLs {
                folderInfoLoadingState[url] = true
            }

            // Scan in batches to avoid I/O saturation
            var results: [(URL, EnhancedFolderInfo?)] = []
            let chunkSize = 6
            var index = 0

            while index < newURLs.count {
                let end = min(index + chunkSize, newURLs.count)
                let slice = Array(newURLs[index..<end])

                await withTaskGroup(of: (URL, EnhancedFolderInfo?).self) { group in
                    for url in slice {
                        group.addTask {
                            // Lightweight info to avoid scanning large destination volumes
                            let info = await self.getLightweightFolderInfo(for: url)
                            return (url, info)
                        }
                    }
                    for await pair in group {
                        results.append(pair)
                    }
                }
                index = end
            }

            for (url, info) in results {
                destinationFolderInfos[url] = info
                folderInfoLoadingState[url] = false
            }
        }

        // Clean up removed URLs
        let urlSet = Set(urls)
        destinationFolderInfos = destinationFolderInfos.filter { urlSet.contains($0.key) }

        // Keep loading state for source/left/right URLs
        folderInfoLoadingState = folderInfoLoadingState.filter {
            urlSet.contains($0.key) || $0.key == sourceURL || $0.key == leftURL || $0.key == rightURL
        }
    }

    /// Get folder info for any URL (checks all caches)
    func getFolderInfo(for url: URL) -> EnhancedFolderInfo? {
        if url == sourceURL { return sourceFolderInfo }
        if url == leftURL { return leftFolderInfo }
        if url == rightURL { return rightFolderInfo }
        return destinationFolderInfos[url]
    }

    /// Check if folder info is currently loading for a URL
    func isFolderInfoLoading(for url: URL) -> Bool {
        return folderInfoLoadingState[url] ?? false
    }

    /// Clear all cached folder info
    func clearAll() {
        sourceFolderInfo = nil
        leftFolderInfo = nil
        rightFolderInfo = nil
        destinationFolderInfos.removeAll()
        folderInfoLoadingState.removeAll()
        sourceURL = nil
        leftURL = nil
        rightURL = nil
        destinationURLs.removeAll()
    }

    // MARK: - Private Scanning Methods

    /// Full scan for source folders - includes file type breakdown
    nonisolated private func getEnhancedFolderInfo(for url: URL) async -> EnhancedFolderInfo? {
        return await Task.detached(priority: .userInitiated) {
            var fileCount = 0
            var totalSize: Int64 = 0
            var fileTypeBreakdown: [String: Int] = [:]
            var largestFile: (name: String, size: Int64)? = nil
            var oldestFile: Date? = nil
            var newestFile: Date? = nil

            let fileEnumKeys: [URLResourceKey] = [
                .isRegularFileKey,
                .fileSizeKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
                .nameKey
            ]

            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: fileEnumKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return nil
            }

            while let file = enumerator.nextObject() {
                autoreleasepool {
                    guard let fileURL = file as? URL else { return }
                    guard let rv = try? fileURL.resourceValues(forKeys: Set(fileEnumKeys)) else { return }
                    if rv.isSymbolicLink == true { return }

                    if rv.isRegularFile == true {
                        fileCount += 1
                        let fileSize = Int64(rv.fileSize ?? 0)
                        totalSize += fileSize

                        let fileExtension = fileURL.pathExtension.uppercased()
                        let displayExtension = fileExtension.isEmpty ? "No Extension" : fileExtension
                        fileTypeBreakdown[displayExtension, default: 0] += 1

                        if let lf = largestFile {
                            if fileSize > lf.size {
                                largestFile = (name: fileURL.lastPathComponent, size: fileSize)
                            }
                        } else {
                            largestFile = (name: fileURL.lastPathComponent, size: fileSize)
                        }

                        if let modDate = rv.contentModificationDate {
                            if let oldest = oldestFile {
                                if modDate < oldest { oldestFile = modDate }
                            } else {
                                oldestFile = modDate
                            }
                            if let newest = newestFile {
                                if modDate > newest { newestFile = modDate }
                            } else {
                                newestFile = modDate
                            }
                        }

                        if fileCount % 5000 == 0 && fileCount > 0 {
                            let formatted = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
                            SharedLogger.debug("FolderInfo: analyzed \(fileCount) files, size=\(formatted) at \(url.path)", category: .transfer)
                        }
                    }
                }
            }

            let folderModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

            return EnhancedFolderInfo(
                url: url,
                fileCount: fileCount,
                totalSize: totalSize,
                lastModified: folderModified,
                isInternalDrive: !url.path.starts(with: "/Volumes/"),
                fileTypeBreakdown: fileTypeBreakdown,
                largestFile: largestFile,
                oldestFileDate: oldestFile,
                newestFileDate: newestFile
            )
        }.value
    }

    /// Lightweight scan for destination folders - just basic metadata
    nonisolated private func getLightweightFolderInfo(for url: URL) async -> EnhancedFolderInfo? {
        return await Task.detached(priority: .utility) {
            let lastMod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return EnhancedFolderInfo(
                url: url,
                fileCount: 0,
                totalSize: 0,
                lastModified: lastMod,
                isInternalDrive: !url.path.starts(with: "/Volumes/"),
                fileTypeBreakdown: [:],
                largestFile: nil,
                oldestFileDate: nil,
                newestFileDate: nil
            )
        }.value
    }
}
