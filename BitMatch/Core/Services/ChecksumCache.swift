import Foundation
import CryptoKit

/// Caches checksums to avoid recomputing for identical files
actor ChecksumCache {
    static let shared = ChecksumCache()
    
    private struct CacheKey: Hashable {
        let inode: UInt64
        let deviceID: Int32
        let modificationTime: Date
        let size: Int64
        let algorithm: ChecksumAlgorithm
    }
    
    private struct CacheEntry {
        let checksum: String
        let computedAt: Date
    }
    
    private var cache: [CacheKey: CacheEntry] = [:]
    private let maxCacheSize = 10_000
    private let cacheExpirationTime: TimeInterval = 3600 // 1 hour
    
    private init() {}
    
    // Get cached checksum if available
    func getCachedChecksum(for url: URL, algorithm: ChecksumAlgorithm) -> String? {
        guard let key = makeCacheKey(for: url, algorithm: algorithm) else {
            return nil
        }
        
        if let entry = cache[key] {
            // Check if cache entry is still valid
            if Date().timeIntervalSince(entry.computedAt) < cacheExpirationTime {
                return entry.checksum
            } else {
                // Remove expired entry
                cache.removeValue(forKey: key)
            }
        }
        
        return nil
    }
    
    // Store computed checksum
    func cacheChecksum(_ checksum: String, for url: URL, algorithm: ChecksumAlgorithm) {
        guard let key = makeCacheKey(for: url, algorithm: algorithm) else {
            return
        }
        
        // Implement simple LRU by removing oldest entries if cache is too large
        if cache.count >= maxCacheSize {
            // Remove oldest 20% of entries
            let toRemove = cache.count / 5
            let sortedKeys = cache.sorted { $0.value.computedAt < $1.value.computedAt }
            for (key, _) in sortedKeys.prefix(toRemove) {
                cache.removeValue(forKey: key)
            }
        }
        
        cache[key] = CacheEntry(checksum: checksum, computedAt: Date())
    }
    
    // Clear entire cache
    func clearCache() {
        cache.removeAll()
    }
    
    // Clear expired entries
    func cleanupExpired() {
        let now = Date()
        cache = cache.filter { _, entry in
            now.timeIntervalSince(entry.computedAt) < cacheExpirationTime
        }
    }
    
    private func makeCacheKey(for url: URL, algorithm: ChecksumAlgorithm) -> CacheKey? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            
            guard let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                  let deviceID = (attributes[.deviceIdentifier] as? NSNumber)?.int32Value,
                  let modificationDate = attributes[.modificationDate] as? Date,
                  let size = (attributes[.size] as? NSNumber)?.int64Value else {
                return nil
            }
            
            return CacheKey(
                inode: inode,
                deviceID: deviceID,
                modificationTime: modificationDate,
                size: size,
                algorithm: algorithm
            )
        } catch {
            return nil
        }
    }
}
