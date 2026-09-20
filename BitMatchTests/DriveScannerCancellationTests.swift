import Foundation
import Testing
@testable import BitMatch

/// Report scans walk whole volumes, so they check for cancellation
/// cooperatively. These lock in that a cancelled scan still returns
/// cleanly instead of hanging or throwing.
struct DriveScannerCancellationTests {
    @Test func emptyScanReturnsNoTransfers() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let transfers = await DriveScanner.scanForBitMatchReports(at: dir)
        #expect(transfers.isEmpty)
    }

    @Test func cancelledScanReturnsCleanly() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let task = Task { await DriveScanner.scanForBitMatchReports(at: dir) }
        task.cancel()
        let transfers = await task.value
        #expect(transfers.isEmpty)
    }
}
