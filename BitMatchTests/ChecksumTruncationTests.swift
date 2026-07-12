import XCTest
@testable import BitMatch

/// Regression tests for checksum behavior when a file shrinks mid-read
/// (failing card, yanked drive, concurrent writer).
/// The hash loops previously broke out silently on a short read and
/// returned a checksum of partial content as if it were complete, and the
/// paranoid byte-comparison spun forever when both files hit EOF early.
final class ChecksumTruncationTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecksumTruncationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String, size: Int) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        var bytes = Data(count: size)
        bytes.withUnsafeMutableBytes { buffer in
            for i in 0..<buffer.count { buffer[i] = UInt8(i % 251) }
        }
        try bytes.write(to: url)
        return url
    }

    private func truncate(_ url: URL, to size: UInt64) {
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            XCTFail("Could not open \(url.path) for truncation")
            return
        }
        try? handle.truncate(atOffset: size)
        try? handle.close()
    }

    private func appendByte(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xff]))
    }

    func testChecksumThrowsWhenFileShrinksMidHash() async throws {
        // 256KB = 4 x 64KB chunks; truncate to one chunk after the first
        // progress callback so subsequent reads hit EOF early.
        let file = try makeFile("shrinking.bin", size: 256 * 1024)
        let truncated = ThreadSafeFlag()

        do {
            _ = try await SharedChecksumService.shared.generateChecksum(
                for: file,
                type: .sha256,
                useCache: false
            ) { [self] _, _ in
                if !truncated.getAndSet() {
                    truncate(file, to: 64 * 1024)
                }
            }
            XCTFail("Expected checksum of a shrinking file to throw")
        } catch {
            // Expected: incomplete read must surface as an error.
        }
    }

    func testByteComparisonThrowsInsteadOfHangingWhenBothFilesShrink() async throws {
        let source = try makeFile("src.bin", size: 256 * 1024)
        let destination = try makeFile("dst.bin", size: 256 * 1024)
        let truncated = ThreadSafeFlag()

        let task = Task {
            try await SharedChecksumService.shared.performByteComparison(
                sourceURL: source,
                destinationURL: destination
            ) { [self] _, _ in
                if !truncated.getAndSet() {
                    truncate(source, to: 64 * 1024)
                    truncate(destination, to: 64 * 1024)
                }
            }
        }

        let outcome = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                let result = await task.result
                if case .success = result {
                    return false // must not report a verdict for a shrinking file
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return false // timed out: the comparison hung
            }
            let first = await group.next() ?? false
            task.cancel()
            group.cancelAll()
            return first
        }

        XCTAssertTrue(outcome, "Byte comparison must throw promptly when files shrink mid-compare")
    }

    func testChecksumThrowsWhenFileGrowsAfterFinalChunk() async throws {
        let file = try makeFile("growing-hash.bin", size: 64 * 1024)
        let appended = ThreadSafeFlag()

        do {
            _ = try await SharedChecksumService.shared.generateChecksum(
                for: file,
                type: .sha256,
                useCache: false
            ) { [self] progress, _ in
                if progress >= 1, !appended.getAndSet() {
                    try? appendByte(to: file)
                }
            }
            XCTFail("Expected checksum of a growing file to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("changed while reading"))
        }
    }

    func testByteComparisonThrowsWhenFileGrowsAfterFinalChunk() async throws {
        let source = try makeFile("growing-source.bin", size: 64 * 1024)
        let destination = try makeFile("growing-destination.bin", size: 64 * 1024)
        let appended = ThreadSafeFlag()

        do {
            _ = try await SharedChecksumService.shared.performByteComparison(
                sourceURL: source,
                destinationURL: destination
            ) { [self] progress, _ in
                if progress >= 1, !appended.getAndSet() {
                    try? appendByte(to: source)
                }
            }
            XCTFail("Expected byte comparison of a growing file to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("changed while reading"))
        }
    }

    func testChecksumOfStableFileStillSucceeds() async throws {
        let file = try makeFile("stable.bin", size: 256 * 1024)
        let checksum = try await SharedChecksumService.shared.generateChecksum(
            for: file,
            type: .sha256,
            useCache: false,
            progressCallback: nil
        )
        XCTAssertEqual(checksum.count, 64)
    }
}

/// Progress callbacks may run on any thread; guard the truncation flag.
private final class ThreadSafeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func getAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = true
        return old
    }
}
