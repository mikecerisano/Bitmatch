// Shared/Core/Services/File/BackupTargetPolicy.swift
//
// The one rule for what may become a backup, used by every path that adds
// one: the pickers and drag-and-drop, Mac drive discovery, the Mac's
// launch-time restore of last-used backups, queue replay, the debug tools,
// the readiness check and the engine's own preflight.
//
// Where the line is:
//
// - Never, whoever asks: the startup disk itself ("/", which is also what
//   /Volumes/Macintosh HD resolves to), anything under /System (the Data
//   sibling at /System/Volumes/Data, Preboot, Recovery, VM, Update, ...),
//   the root of the boot volume, the root of an internal volume with a
//   system name (Recovery, "Recovery 2", Preboot, ...), the root of the
//   source's own volume, and any folder on the source's volume when that
//   volume is removable (a card: Promise 1, the card is sacred).
// - A folder the user picks on the internal disk is allowed (the GitHub #8
//   setup: a real backup folder on Macintosh HD), and so is a folder on the
//   same fixed disk as the source (the debug stress test) or in the temp
//   folders, including a disk image mounted there (the APFS fault tests).
// - Restoring last time's backups at launch also refuses anything in the
//   temp folders (a volume mounted there included) and internal volume
//   roots: the stress test's temp folder, or a system volume that an older
//   build auto-added and saved, must not come back.
// - Drive discovery adds only whole external or removable volumes, never a
//   system-named one, and never the source's volume.
//
// Discovery and restore refuse silently (the callers log); a user's own
// pick gets `message` back to show.
import Foundation

enum BackupTargetPolicy {
    /// Who is adding the backup.
    enum Origin: Equatable, Sendable {
        /// The user picked or dropped it (also queue replay, whose backups
        /// the user picked when queuing, and the debug tools).
        case userChoice
        /// Put back at launch from last time's list.
        case restored
        /// Found by Mac drive discovery.
        case discovered
    }

    /// What the file system says about the volume a folder is on. Read by
    /// `read(_:)`; tests pass their own.
    struct VolumeFacts: Equatable, Sendable {
        /// The volume's mount point, symlinks resolved.
        var volumeRootPath: String
        /// The volume UUID, when the file system has one.
        var volumeID: String?
        var volumeName: String?
        /// The sealed system volume mounted at "/".
        var isRootFileSystem: Bool
        /// nil when the system does not say.
        var isInternal: Bool?
        var isRemovable: Bool
        var isEjectable: Bool

        /// Facts for the volume holding `url`, or nil when they cannot be
        /// read (nothing there, or no access).
        static func read(_ url: URL) -> VolumeFacts? {
            let resolved = URL(fileURLWithPath: BackupTargetPolicy.canonicalPath(url))
            guard let values = try? resolved.resourceValues(forKeys: [
                .volumeURLKey,
                .volumeUUIDStringKey,
                .volumeNameKey,
                .volumeIsRootFileSystemKey,
                .volumeIsInternalKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey
            ]), let volumeURL = values.volume else {
                return nil
            }
            return VolumeFacts(
                volumeRootPath: BackupTargetPolicy.canonicalPath(volumeURL),
                volumeID: values.volumeUUIDString,
                volumeName: values.volumeName,
                isRootFileSystem: values.volumeIsRootFileSystem ?? false,
                isInternal: values.volumeIsInternal,
                isRemovable: values.volumeIsRemovable ?? false,
                isEjectable: values.volumeIsEjectable ?? false
            )
        }

        var isRemovableMedia: Bool { isRemovable || isEjectable }
    }

    /// Why `target` may not be added as a backup by `origin`, or nil when
    /// it may. Pure apart from resolving symlinks in the two paths; volume
    /// facts come from `facts`.
    static func refusal(
        for target: URL,
        origin: Origin,
        source: URL?,
        facts: (URL) -> VolumeFacts? = VolumeFacts.read,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> String? {
        let path = canonicalPath(target)
        let name = target.path == "/" ? "This" : target.lastPathComponent
        let targetFacts = facts(target)
        let isVolumeRoot = targetFacts.map { $0.volumeRootPath == path } ?? false
        let temporaryRoots = temporaryRootPaths(temporaryDirectory)

        // Never, whoever asks.
        if path == "/" {
            return "\(name) is the startup disk. Choose a folder on it instead."
        }
        if isWithin(path, root: "/System") {
            return "\(name) is a macOS system volume and cannot be a backup."
        }
        if let targetFacts, isVolumeRoot {
            if targetFacts.isRootFileSystem {
                return "\(name) is the startup disk. Choose a folder on it instead."
            }
            if targetFacts.isInternal == true, isSystemVolumeName(targetFacts.volumeName ?? name) {
                return "\(name) is a macOS system volume and cannot be a backup."
            }
        }
        if let source, let targetFacts, let sourceFacts = facts(source),
           sameVolume(targetFacts, sourceFacts) {
            if isVolumeRoot {
                return "\(name) is the source's own drive and cannot be its backup."
            }
            if sourceFacts.isRemovableMedia {
                return "\(name) is on the same card as the source. BitMatch never writes to the source card."
            }
            // A folder on the source's fixed disk stays allowed when picked
            // (the stress test); discovery only adds whole drives, so the
            // root check above already keeps the source's drive out of it.
        }

        switch origin {
        case .userChoice:
            return nil
        case .restored, .discovered:
            // An automatic add must be able to see what it is adding.
            guard let targetFacts else {
                return "\(name) cannot be inspected."
            }
            // Anything in the temp folders, a volume mounted there included.
            // (A user may still pick one: the APFS fault harness mounts its
            // disposable backup volume under $TMPDIR.)
            if temporaryRoots.contains(where: { isWithin(path, root: $0) }) {
                return "\(name) is a temporary folder."
            }
            if isVolumeRoot, targetFacts.isInternal != false, !targetFacts.isRemovableMedia {
                return "\(name) is an internal volume."
            }
            guard origin == .discovered else { return nil }
            if !isVolumeRoot {
                return "\(name) is not a whole drive."
            }
            if isSystemVolumeName(targetFacts.volumeName ?? name) || isSystemVolumeName(name) {
                return "\(name) has a macOS system volume name."
            }
            return nil
        }
    }

    // MARK: - Helpers

    /// Recovery, "Recovery 2", Preboot, "Macintosh HD - Data", ...: the APFS
    /// system roles and the duplicate-mount names macOS gives them.
    static func isSystemVolumeName(_ name: String) -> Bool {
        if name.hasSuffix(" - Data") { return true }
        var base = Substring(name)
        if let space = base.lastIndex(of: " "),
           base[base.index(after: space)...].allSatisfy(\.isNumber),
           base.index(after: space) < base.endIndex {
            base = base[..<space]
        }
        return systemVolumeNames.contains(String(base))
    }

    private static let systemVolumeNames: Set<String> = [
        "Macintosh HD", "System", "Data", "Preboot", "Recovery", "VM",
        "Update", "Hardware", "xART", "xarts", "iSCPreboot"
    ]

    private static func temporaryRootPaths(_ temporaryDirectory: URL) -> [String] {
        [canonicalPath(temporaryDirectory), "/private/var/folders", "/private/tmp", "/var/folders", "/tmp"]
    }

    private static func sameVolume(_ lhs: VolumeFacts, _ rhs: VolumeFacts) -> Bool {
        if let left = lhs.volumeID, let right = rhs.volumeID { return left == right }
        return lhs.volumeRootPath == rhs.volumeRootPath
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isWithin(_ path: String, root: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        guard pathComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, pathComponents).allSatisfy(==)
    }
}
