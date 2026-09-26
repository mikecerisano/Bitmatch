// ResultPathMatch.swift - Path text for matching written files to their backup.
import Foundation

/// Path text for deciding which backup a written file belongs to, without
/// touching the disk (the files may be gone, and there can be 100k rows).
enum ResultPathMatch {
    /// `/private/var`, `/private/tmp` and `/private/etc` are where macOS's
    /// `/var`, `/tmp` and `/etc` symlinks point, so both spellings compare equal.
    static func comparablePath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        for linked in ["/var", "/tmp", "/etc"] where
            standardized == "/private" + linked || standardized.hasPrefix("/private" + linked + "/") {
            return String(standardized.dropFirst("/private".count))
        }
        return standardized
    }
}
