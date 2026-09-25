// IOSStoragePathTests.swift
// On a physical iPhone or iPad, folders from the Files picker (On My iPad,
// iCloud Drive, external drives under LiveFiles) live below
// /private/var/mobile. The Mac's system-folder rule refuses /private and
// /var, which would refuse every backup on a device. The simulator cannot
// show it: its paths are under the Mac's /Users.
import Foundation
import Testing
@testable import BitMatch_iPad

struct IOSStoragePathTests {
    /// Fails if `SafetyValidator.isProtectedSystemPath` stops exempting the
    /// mobile user's storage on iOS.
    @Test func filesPickerLocationsAreNotSystemFolders() {
        let userStorage = [
            "/private/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/T7/Backups",
            "/private/var/mobile/Containers/Shared/AppGroup/1A2B3C4D/File Provider Storage/Backups",
            "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Backups",
            "/var/mobile/Containers/Data/Application/5E6F/Documents/Backups",
        ]
        for path in userStorage {
            #expect(!SafetyValidator.isProtectedSystemPath(URL(fileURLWithPath: path, isDirectory: true)), "\(path)")
        }
    }

    /// The exemption is the mobile user's storage only.
    @Test func systemFoldersStayProtected() {
        for path in ["/System/Library", "/private/var/root", "/private/etc", "/var/db", "/usr/lib"] {
            #expect(SafetyValidator.isProtectedSystemPath(URL(fileURLWithPath: path, isDirectory: true)), "\(path)")
        }
    }
}
