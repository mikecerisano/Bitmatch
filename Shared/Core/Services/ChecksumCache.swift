// ChecksumCache.swift - Cross-platform persistent checksum cache
import Foundation
import CryptoKit

actor SharedChecksumCache {
    static let shared = SharedChecksumCache()

    struct Key: Hashable, Codable {
        let path: String
        let algorithm: String
        let fileSize: Int64
        let modTime: TimeInterval
        let inode: UInt64  // Bug 3 fix: track inode to detect hard links
    }

    private struct Entry: Codable {
        let checksum: String
        let timestamp: Date
    }

    private var cache: [Key: Entry] = [:]
    private var accessOrder: [Key] = [] // Perf 10: LRU tracking
    private let maxCapacity = 50_000     // Perf 10: max cache entries
    private let ttl: TimeInterval = 60 * 60 // 1 hour
    private let fileURL: URL
    private var savePending = false      // Perf 10: debounce disk writes
    private var lastSaveTime = Date.distantPast

    /// Security 15: hash a path using SHA256 so plaintext paths are not stored on disk
    private static func hashPath(_ path: String) -> String {
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = dir.appendingPathComponent("com.bitmatch.app", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("checksum_cache.json")
        // Security 15: set file protection on iOS
        #if os(iOS)
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
        #endif
        // Load existing cache from disk synchronously in initializer (allowed)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Key: Entry].self, from: data) {
            cache = decoded
        }
    }

    // Perf 10: debounce saves to every 5 seconds
    private func scheduleSave() {
        let now = Date()
        if now.timeIntervalSince(lastSaveTime) >= 5.0 {
            saveToDisk()
        } else if !savePending {
            savePending = true
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.flushPendingSave()
            }
        }
    }

    private func flushPendingSave() {
        guard savePending else { return }
        savePending = false
        saveToDisk()
    }

    private func saveToDisk() {
        lastSaveTime = Date()
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // Perf 10: evict least-recently-used entries when over capacity
    private func evictIfNeeded() {
        guard cache.count > maxCapacity else { return }
        let excess = cache.count - maxCapacity
        let keysToRemove = Array(accessOrder.prefix(excess))
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        accessOrder.removeFirst(min(excess, accessOrder.count))
    }

    private func touchKey(_ key: Key) {
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
    }

    func get(for url: URL, algorithm: String) -> String? {
        // Bug 3 fix: resolve symlinks before lookup
        let resolvedURL = url.resolvingSymlinksInPath()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
              let size = attrs[.size] as? NSNumber,
              let modDate = attrs[.modificationDate] as? Date,
              let inode = attrs[.systemFileNumber] as? UInt64 else { return nil }
        // Security 15: hash path so plaintext paths aren't stored
        let key = Key(path: Self.hashPath(resolvedURL.path), algorithm: algorithm, fileSize: size.int64Value, modTime: modDate.timeIntervalSince1970, inode: inode)
        if let entry = cache[key] {
            if Date().timeIntervalSince(entry.timestamp) < ttl {
                touchKey(key) // Perf 10: mark as recently used
                return entry.checksum
            }
        }
        return nil
    }

    func set(_ checksum: String, for url: URL, algorithm: String) {
        // Bug 3 fix: resolve symlinks before storing
        let resolvedURL = url.resolvingSymlinksInPath()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
              let size = attrs[.size] as? NSNumber,
              let modDate = attrs[.modificationDate] as? Date,
              let inode = attrs[.systemFileNumber] as? UInt64 else { return }
        // Security 15: hash path so plaintext paths aren't stored
        let key = Key(path: Self.hashPath(resolvedURL.path), algorithm: algorithm, fileSize: size.int64Value, modTime: modDate.timeIntervalSince1970, inode: inode)
        cache[key] = Entry(checksum: checksum, timestamp: Date())
        touchKey(key) // Perf 10: mark as recently used
        evictIfNeeded() // Perf 10: enforce max capacity
        scheduleSave() // Perf 10: debounced disk write
    }
}
