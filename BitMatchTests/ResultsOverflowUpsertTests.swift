import XCTest
@testable import BitMatch

/// Regression tests for the copy-row / verify-row race.
/// CopyVerifyExecutor previously dispatched each file result in an unordered
/// Task and did a check-then-act (updateResult else addResult) across two
/// actor hops. If a verify row (including a checksum mismatch) was processed
/// before its copy row, the later "✅ Copied" row replaced it and the corrupt
/// file was reported as verified.
final class ResultsOverflowUpsertTests: XCTestCase {

    private func row(_ path: String, status: String, destinationPath: String = "/Volumes/Backup/A") -> ResultRow {
        ResultRow(
            path: path,
            status: status,
            size: 100,
            checksum: nil,
            destination: "Backup",
            destinationPath: destinationPath
        )
    }

    func testCopyRowCannotReplaceVerifyFailureRow() async {
        let service = ResultsOverflowService(operationId: UUID())
        await service.upsert(row("/src/a.mov", status: "⚠️ Checksum Mismatch"))
        await service.upsert(row("/src/a.mov", status: "✅ Copied"))

        let results = await service.getAllResults()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, "⚠️ Checksum Mismatch")
    }

    func testVerifyRowReplacesCopyRow() async {
        let service = ResultsOverflowService(operationId: UUID())
        await service.upsert(row("/src/a.mov", status: "✅ Copied"))
        await service.upsert(row("/src/a.mov", status: "✅ Verified"))

        let results = await service.getAllResults()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, "✅ Verified")
    }

    func testVerifyFailureReplacesCopyRow() async {
        let service = ResultsOverflowService(operationId: UUID())
        await service.upsert(row("/src/a.mov", status: "✅ Copied"))
        await service.upsert(row("/src/a.mov", status: "⚠️ Checksum Mismatch"))

        let results = await service.getAllResults()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, "⚠️ Checksum Mismatch")
    }

    func testDistinctDestinationsKeepSeparateRows() async {
        let service = ResultsOverflowService(operationId: UUID())
        await service.upsert(row("/src/a.mov", status: "✅ Verified", destinationPath: "/Volumes/A/a.mov"))
        await service.upsert(row("/src/a.mov", status: "⚠️ Checksum Mismatch", destinationPath: "/Volumes/B/a.mov"))

        let results = await service.getAllResults()
        XCTAssertEqual(results.count, 2)
    }

    func testCopyRowCannotOverrideVerifyRowSpilledToDisk() async {
        // Force the verify-failure row out of memory onto disk, then attempt
        // the late copy-row upsert; coalescing must still keep the failure.
        let service = ResultsOverflowService(operationId: UUID(), maxInMemoryResults: 1)
        await service.upsert(row("/src/a.mov", status: "⚠️ Checksum Mismatch"))
        await service.upsert(row("/src/b.mov", status: "✅ Verified")) // spills a.mov to disk
        await service.upsert(row("/src/a.mov", status: "✅ Copied"))

        let results = await service.getAllResults()
        let rowA = results.first { $0.path == "/src/a.mov" }
        XCTAssertEqual(rowA?.status, "⚠️ Checksum Mismatch")
        await service.clear()
    }
}
