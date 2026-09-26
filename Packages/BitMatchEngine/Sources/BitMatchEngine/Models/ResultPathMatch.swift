// ResultPathMatch.swift - Path text for matching written files to their backup.
import Foundation

/// Path text for deciding which backup a written file belongs to, without
/// touching the disk (the files may be gone, and there can be 100k rows).
public enum ResultPathMatch {
    /// `/private/var`, `/private/tmp` and `/private/etc` are where macOS's
    /// `/var`, `/tmp` and `/etc` symlinks point, so both spellings compare equal.
    public static func comparablePath(_ path: String) -> String {
        PathContainment.comparablePath(path)
    }
}
