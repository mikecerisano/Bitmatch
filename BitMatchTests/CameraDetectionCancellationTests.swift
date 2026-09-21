// CameraDetectionCancellationTests.swift
import Foundation
import Testing
@testable import BitMatch

/// Camera detection honors task cancellation: a cancelled task returns
/// nil instead of running the full detector hierarchy (enumeration plus
/// metadata subprocesses).
struct CameraDetectionCancellationTests {
    private func makeCameraDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("MISC"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("DCIM/f1.jpg"))
        return dir
    }

    @Test func cancelledDetectionReturnsNil() async throws {
        #if os(macOS)
        let dir = try makeCameraDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Sanity: uncancelled detection finds the camera marker.
        #expect(CameraDetectionOrchestrator.shared.detectCamera(at: dir) != nil)

        let task = Task.detached { CameraDetectionOrchestrator.shared.detectCamera(at: dir) }
        task.cancel()
        #expect(await task.value == nil)
        #else
        #expect(true)
        #endif
    }

    /// Cancellation must abort a parse loop already underway. This targets
    /// one detector stage directly: unlike the full hierarchy (where stage
    /// boundaries alone abort later stages), here only the in-loop check
    /// can stop the work. The threshold is calibrated against a full
    /// uncancelled run on the same machine seconds earlier.
    @Test func cancelledMidFlightParseLoopAborts() async throws {
        #if os(macOS)
        // Many large XML files with no camera tags: every file pays full
        // read-plus-regex cost and matches nothing, so the loop itself is
        // the slow work. Returns nil with or without the fix; only the
        // abort timing discriminates.
        let dir = try makeBigXMLDir(files: 500, kilobytesEach: 200)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fullStart = ContinuousClock.now
        let fullResult = XMLMetadataDetectionService.shared.detectCameraFromXML(at: dir)
        let fullElapsed = ContinuousClock.now - fullStart
        #expect(fullResult == nil)
        // Headroom for the abort threshold below; on absurdly fast hardware
        // the cancel window cannot be distinguished from instant completion.
        guard fullElapsed > .seconds(1) else { return }

        let started = CompletionFlag()
        let finished = CompletionFlag()
        let task = Task.detached {
            defer { finished.set() }
            return XMLMetadataDetectionService.shared.detectCameraFromXML(at: dir) {
                started.set()
            }
        }
        // Prove execution started: the task entered the enumeration before
        // it is cancelled, so this is a mid-flight abort by construction.
        for _ in 0..<500 {
            if started.get() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(started.get(), "detection never entered its enumeration")
        #expect(!finished.get())
        task.cancel()
        let abortStart = ContinuousClock.now
        let result = await task.value
        let abortElapsed = ContinuousClock.now - abortStart
        #expect(result == nil)
        #expect(abortElapsed < fullElapsed / 3)
        #else
        #expect(true)
        #endif
    }

    private func makeBigXMLDir(files: Int, kilobytesEach: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paragraph = String(repeating: "<note>field performance log entry with filler text</note>\n", count: 4)
        let repeats = max(1, (kilobytesEach * 1024) / max(1, paragraph.utf8.count))
        let payload = String(repeating: paragraph, count: repeats)
        for index in 0..<files {
            try payload.write(to: dir.appendingPathComponent("meta_\(index).xml"), atomically: true, encoding: .utf8)
        }
        return dir
    }
}

private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.withLock { value = true }
    }

    func get() -> Bool {
        lock.withLock { value }
    }
}
