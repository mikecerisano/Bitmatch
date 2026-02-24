// TestFixtures.swift
// BitMatchTests
//
// Test helper functions for creating temporary files, directories,
// and file trees used across the BitMatch test suite.

import Foundation
import XCTest

// MARK: - Free Functions

/// Creates a unique temporary directory for test use.
/// The caller is responsible for cleanup via `cleanupTempDirectory(_:)`.
func createTempDirectory() -> URL {
    let tmp = FileManager.default.temporaryDirectory
    let directory = tmp.appendingPathComponent("bitmatch_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Creates a single file filled with random data in the given directory.
/// - Parameters:
///   - directory: The parent directory where the file will be created.
///   - name: The file name (e.g. "sample.bin").
///   - size: The number of random bytes to write.
/// - Returns: The URL of the newly created file.
func createSampleFile(in directory: URL, name: String, size: Int) throws -> URL {
    let fileURL = directory.appendingPathComponent(name)
    let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
    try data.write(to: fileURL, options: .atomic)
    return fileURL
}

/// Creates multiple files with random data inside the given directory.
/// Files are named sequentially as "file_0.bin", "file_1.bin", etc.
/// - Parameters:
///   - directory: The parent directory where files will be created.
///   - fileCount: The number of files to create.
///   - fileSize: The byte size of each file.
/// - Returns: An array of URLs for the created files.
func createSampleFileTree(in directory: URL, fileCount: Int, fileSize: Int) throws -> [URL] {
    var urls: [URL] = []
    for index in 0..<fileCount {
        let url = try createSampleFile(in: directory, name: "file_\(index).bin", size: fileSize)
        urls.append(url)
    }
    return urls
}

/// Removes a temporary directory and all of its contents.
/// Failures are silently ignored so cleanup never throws in teardown.
func cleanupTempDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - TestFixture Class

/// A convenience wrapper that manages a temporary directory for the
/// lifetime of the object. The directory is created on `init` and
/// automatically removed in `deinit`, making it suitable for use as
/// a stored property in test classes.
///
/// Usage:
/// ```
/// let fixture = TestFixture()
/// let file = try createSampleFile(in: fixture.directory, name: "a.bin", size: 512)
/// // directory is cleaned up when `fixture` goes out of scope
/// ```
class TestFixture {
    /// The temporary directory managed by this fixture.
    let directory: URL

    /// Creates a new fixture with a unique temporary directory.
    init() {
        self.directory = createTempDirectory()
    }

    /// Removes the temporary directory and all of its contents.
    deinit {
        cleanupTempDirectory(directory)
    }
}
