import CryptoKit
import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#endif
@testable import BitMatch

/// Promise 1, "the card is sacred": a transfer leaves every entry in the
/// source tree exactly as it found it. Nothing is added, removed, rewritten,
/// resized, re-dated, or re-permissioned, in any verification mode.
final class SourceTreeUnchangedTests: XCTestCase {
    func testTransferLeavesSourceTreeUnchangedInEveryVerificationMode() async throws {
        try await FileOperationsTestLock.shared.run {
            for mode in VerificationMode.allCases {
                let fixture = try DisposableTransferFixture(
                    seed: 20_260_925,
                    fileCount: 6,
                    bytesPerFile: 64 * 1024
                )
                defer { fixture.cleanup() }
                let source = sourceTreeCanonicalDirectoryURL(fixture.source)
                let before = try SourceTreeSnapshot(root: source)

                let operation = try await SharedFileOperationsService(
                    fileSystem: MacOSFileSystemService.shared,
                    checksum: SharedChecksumService.shared
                ).performFileOperation(
                    sourceURL: source,
                    destinationURLs: fixture.destinations,
                    verificationMode: mode,
                    settings: CameraLabelSettings(),
                    estimatedTotalBytes: nil,
                    progressCallback: { _ in },
                    onFileResult: nil
                )

                // Guard against a vacuous pass: the transfer must actually
                // have read every source file.
                XCTAssertEqual(
                    operation.results.count,
                    fixture.manifest.count * fixture.destinations.count,
                    "\(mode.rawValue): unexpected result count"
                )
                XCTAssertTrue(
                    operation.results.allSatisfy(\.success),
                    "\(mode.rawValue): transfer reported failures"
                )

                let after = try SourceTreeSnapshot(root: source)
                XCTAssertEqual(
                    after.entries.keys.sorted(),
                    before.entries.keys.sorted(),
                    "\(mode.rawValue): entries were added to or removed from the source"
                )
                for (path, entry) in before.entries.sorted(by: { $0.key < $1.key }) {
                    XCTAssertEqual(
                        after.entries[path],
                        entry,
                        "\(mode.rawValue): source entry '\(path)' changed"
                    )
                }
            }
        }
    }
}

/// Every file and directory under a root, including hidden entries and the
/// root itself (key "."). Directory modification dates catch entries that
/// were created and then removed during the transfer.
private struct SourceTreeSnapshot {
    struct Entry: Equatable {
        let isDirectory: Bool
        let size: Int64
        let modificationDate: Date?
        let posixPermissions: Int?
        let sha256: String?
    }

    let entries: [String: Entry]

    init(root: URL) throws {
        let fileManager = FileManager.default
        var entries: [String: Entry] = [:]
        let relativePaths = try fileManager.subpathsOfDirectory(atPath: root.path)
        for relativePath in ["."] + relativePaths {
            let url = relativePath == "." ? root : root.appendingPathComponent(relativePath)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            let isDirectory = type == .typeDirectory
            let sha256: String?
            if type == .typeRegular {
                let data = try Data(contentsOf: url)
                sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            } else {
                sha256 = nil
            }
            entries[relativePath] = Entry(
                isDirectory: isDirectory,
                size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                modificationDate: attributes[.modificationDate] as? Date,
                posixPermissions: (attributes[.posixPermissions] as? NSNumber)?.intValue,
                sha256: sha256
            )
        }
        self.entries = entries
    }
}

private func sourceTreeCanonicalDirectoryURL(_ url: URL) -> URL {
    #if canImport(Darwin)
    guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    #else
    return url.resolvingSymlinksInPath().standardizedFileURL
    #endif
}
