// MockChecksumService.swift
// BitMatchTests
//
// A mock checksum service for unit testing. Allows tests to
// pre-configure checksums, control verification results, and
// simulate failure conditions without performing real hashing.

import Foundation
import XCTest

class MockChecksumService {

    // MARK: - State

    /// Pre-configured checksums keyed by file URL.
    /// Populate this before calling `generateChecksum(for:)`.
    var checksums: [URL: String] = [:]

    /// When true, `generateChecksum(for:)` returns nil and
    /// `verifyIntegrity(source:destination:)` returns false.
    var shouldFail = false

    /// The value that `verifyIntegrity(source:destination:)` will
    /// return when `shouldFail` is false.
    var verifyResult = true

    /// Total number of calls to `generateChecksum(for:)`.
    var callCount = 0

    /// Total number of calls to `verifyIntegrity(source:destination:)`.
    private(set) var verifyCallCount = 0

    /// Ordered list of URLs passed to `generateChecksum(for:)`.
    private(set) var generateChecksumURLs: [URL] = []

    /// Ordered list of (source, destination) pairs passed to
    /// `verifyIntegrity(source:destination:)`.
    private(set) var verifyIntegrityCalls: [(source: URL, destination: URL)] = []

    // MARK: - Operations

    /// Returns the pre-configured checksum for the given URL, or nil
    /// if the URL has no entry or `shouldFail` is true.
    func generateChecksum(for url: URL) -> String? {
        callCount += 1
        generateChecksumURLs.append(url)
        if shouldFail { return nil }
        return checksums[url]
    }

    /// Compares the checksums of two URLs. Returns `verifyResult`
    /// when both URLs have matching pre-configured checksums, or
    /// false when `shouldFail` is true.
    func verifyIntegrity(source: URL, destination: URL) -> Bool {
        verifyCallCount += 1
        verifyIntegrityCalls.append((source: source, destination: destination))
        if shouldFail { return false }

        // When both URLs have checksums, compare them; otherwise
        // fall back to the configured verifyResult.
        if let sourceHash = checksums[source],
           let destHash = checksums[destination] {
            return sourceHash == destHash
        }
        return verifyResult
    }

    // MARK: - Convenience

    /// Resets all state back to defaults. Useful in setUp / tearDown.
    func reset() {
        checksums.removeAll()
        shouldFail = false
        verifyResult = true
        callCount = 0
        verifyCallCount = 0
        generateChecksumURLs.removeAll()
        verifyIntegrityCalls.removeAll()
    }
}
