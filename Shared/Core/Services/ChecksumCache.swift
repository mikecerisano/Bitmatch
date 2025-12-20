// ChecksumCache.swift - Cross-platform persistent checksum cache
import Foundation

actor SharedChecksumCache {
    static let shared = SharedChecksumCache()

    struct Key: Hashable, Codable {
        let path: String
        let algorithm: String
        let fileSize: Int64
        let modTime: TimeInterval
    }

    private struct Entry: Codable {
        let checksum: String
        let timestamp: Date
    }

    private var cache: [Key: Entry] = [:]
    private let ttl: TimeInterval = 60 * 60 // 1 hour
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = dir.appendingPathComponent("com.bitmatch.app", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("checksum_cache.json")
        // Load existing cache from disk synchronously in initializer (allowed)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Key: Entry].self, from: data) {
            cache = decoded
        }
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func get(for url: URL, algorithm: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              let modDate = attrs[.modificationDate] as? Date else { return nil }
        let key = Key(path: url.path, algorithm: algorithm, fileSize: size.int64Value, modTime: modDate.timeIntervalSince1970)
        if let entry = cache[key] {
            if Date().timeIntervalSince(entry.timestamp) < ttl {
                return entry.checksum
            }
        }
        return nil
    }

    func set(_ checksum: String, for url: URL, algorithm: String) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              let modDate = attrs[.modificationDate] as? Date else { return }
        let key = Key(path: url.path, algorithm: algorithm, fileSize: size.int64Value, modTime: modDate.timeIntervalSince1970)
        cache[key] = Entry(checksum: checksum, timestamp: Date())
        saveToDisk()
    }
}
