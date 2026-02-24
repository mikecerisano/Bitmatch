// MockFileSystemService.swift
// BitMatchTests
//
// A lightweight in-memory mock for file system operations.
// Use this in unit tests to avoid touching the real file system
// and to simulate error conditions.

import Foundation
import XCTest

class MockFileSystemService {

    // MARK: - State

    /// In-memory store of file URLs to their data contents.
    var files: [URL: Data] = [:]

    /// Set of URLs that represent directories.
    var directories: Set<URL> = []

    /// When true, any read operation will return nil / fail.
    var shouldFailOnRead = false

    /// When true, any write operation will return false / fail.
    var shouldFailOnWrite = false

    // MARK: - Recording

    /// Number of times `addFile(at:data:)` has been called.
    private(set) var addFileCallCount = 0

    /// Number of times `fileExists(at:)` has been called.
    private(set) var fileExistsCallCount = 0

    /// Number of times `getFileSize(for:)` has been called.
    private(set) var getFileSizeCallCount = 0

    // MARK: - Operations

    /// Stores a file with the given data at the specified URL.
    /// If `shouldFailOnWrite` is true the file is not stored.
    func addFile(at url: URL, data: Data) {
        addFileCallCount += 1
        guard !shouldFailOnWrite else { return }
        files[url] = data
    }

    /// Registers a URL as a known directory.
    func addDirectory(at url: URL) {
        directories.insert(url)
    }

    /// Returns true if the URL exists as either a file or a directory.
    func fileExists(at url: URL) -> Bool {
        fileExistsCallCount += 1
        if shouldFailOnRead { return false }
        return files.keys.contains(url) || directories.contains(url)
    }

    /// Returns the size of the file data stored at the URL, or nil
    /// if the file does not exist or reads are configured to fail.
    func getFileSize(for url: URL) -> Int64? {
        getFileSizeCallCount += 1
        if shouldFailOnRead { return nil }
        guard let data = files[url] else { return nil }
        return Int64(data.count)
    }

    // MARK: - Convenience

    /// Reads file data for the given URL. Returns nil when the file
    /// is missing or `shouldFailOnRead` is true.
    func readFile(at url: URL) -> Data? {
        if shouldFailOnRead { return nil }
        return files[url]
    }

    /// Resets all state back to defaults. Useful in setUp / tearDown.
    func reset() {
        files.removeAll()
        directories.removeAll()
        shouldFailOnRead = false
        shouldFailOnWrite = false
        addFileCallCount = 0
        fileExistsCallCount = 0
        getFileSizeCallCount = 0
    }
}
