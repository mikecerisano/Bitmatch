// BackupTargetPolicyRealVolumeTests.swift
// The policy tests use fabricated volume facts. These run the rule against
// real paths and real volume facts on the machine running the tests: a
// home-folder backup (the GitHub #8 setup) must be allowed, and the startup
// disk and a mounted system Recovery volume refused. (/Users is a firmlink
// into /System/Volumes/Data; resolving it must not make home folders look
// like system folders.)
import Foundation
import Testing
@testable import BitMatch

#if os(macOS)
struct BackupTargetPolicyRealVolumeTests {
    /// Fails if canonicalisation or `VolumeFacts.read` makes a home folder
    /// look like a system location (e.g. if firmlinks were followed).
    @Test func realHomeFolderIsAllowedForEveryOrigin() throws {
        let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/bitmatch_realpath_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(BackupTargetPolicy.refusal(for: folder, origin: .userChoice, source: nil) == nil)
        #expect(BackupTargetPolicy.refusal(for: folder, origin: .restored, source: nil) == nil)
    }

    @Test func realStartupDiskIsRefused() {
        #expect(BackupTargetPolicy.refusal(for: URL(fileURLWithPath: "/"), origin: .userChoice, source: nil) != nil)
        #expect(BackupTargetPolicy.refusal(for: URL(fileURLWithPath: "/Volumes/Macintosh HD"), origin: .restored, source: nil) != nil)
    }

    /// Any system Recovery volume mounted on this Mac (macOS mounts them
    /// under /Volumes/Recovery, "Recovery 1", ...) is never restored or
    /// auto-added. Skips the ones that are not mounted.
    @Test func realMountedRecoveryVolumesAreNeverAutoAdded() throws {
        let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        let recoveries = volumes.filter { $0 == "Recovery" || $0.hasPrefix("Recovery ") }
            .map { URL(fileURLWithPath: "/Volumes/\($0)", isDirectory: true) }
            .filter { (try? $0.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) == true }
        for recovery in recoveries {
            #expect(BackupTargetPolicy.refusal(for: recovery, origin: .restored, source: nil) != nil, "\(recovery.path)")
            #expect(BackupTargetPolicy.refusal(for: recovery, origin: .discovered, source: nil) != nil, "\(recovery.path)")
        }
    }
}
#endif
