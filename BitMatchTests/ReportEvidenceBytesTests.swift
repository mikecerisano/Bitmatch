// ReportEvidenceBytesTests.swift
// Promise 3, "the evidence matches reality": report byte figures come from
// what was copied, never from the estimate used for progress. The
// coordinator estimates 1,000,000,000 bytes when the source was not
// measured, and that estimate used to reach the report.
import Foundation
import XCTest
@testable import BitMatch

@MainActor
final class ReportEvidenceBytesTests: XCTestCase {
    /// Fails if `CopyVerifyExecutor.generateReport` passes
    /// `config.estimatedBytes` as `totalBytesProcessed` again.
    func testReportBytesComeFromResultsNotTheEstimate() async throws {
        try await FileOperationsTestLock.shared.run {
            let bytesPerFile = 32 * 1024
            let fixture = try DisposableTransferFixture(seed: 20_260_925, fileCount: 4, bytesPerFile: bytesPerFile)
            defer { fixture.cleanup() }

            let executor = CopyVerifyExecutor(
                platformManager: MacOSPlatformManager.shared,
                timingService: OperationTimingService(),
                errorService: ErrorReportingService(),
                stateService: OperationStateService(),
                backgroundTaskService: IOSBackgroundTaskService.shared
            )
            let config = CopyVerifyConfig(
                operationId: UUID(),
                sourceURL: fixture.source,
                destinationURLs: fixture.destinations,
                verificationMode: .standard,
                cameraLabelSettings: CameraLabelSettings(),
                reportSettings: ReportPrefs(makeReport: true),
                estimatedFiles: fixture.manifest.count,
                estimatedBytes: 1_000_000_000,
                currentMode: .copyAndVerify
            )
            _ = try await executor.execute(
                config: config,
                callbacks: CopyVerifyCallbacks(
                    onProgress: { _ in },
                    onResult: { _ in },
                    onStateChange: { _ in },
                    onAuthoritativeResults: { _ in }
                )
            )

            let reports = fixture.destinations[0].appendingPathComponent("Reports", isDirectory: true)
            let jsonFiles = try FileManager.default
                .contentsOfDirectory(at: reports, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            let jsonURL = try XCTUnwrap(jsonFiles.first, "no JSON report in \(reports.path)")
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL))
            let statistics = try XCTUnwrap((object as? [String: Any])?["statistics"] as? [String: Any])
            let averageFileSize = try XCTUnwrap((statistics["averageFileSize"] as? NSNumber)?.int64Value)

            // The fixture's real files, not the per-file size requested: it
            // also writes a small manifest-style file.
            let sourceBytes = try FileTreeEnumerator.enumerateRegularFiles(base: fixture.source)
                .reduce(Int64(0)) { $0 + $1.size }
            let expected = sourceBytes / Int64(fixture.manifest.count)
            XCTAssertGreaterThan(expected, 0)
            XCTAssertEqual(averageFileSize, expected, "report derived its bytes from the estimate")
        }
    }

    /// Promise 3: the report states only what was measured. Copy and verify
    /// durations were each "half the total" and peak speed "average x 1.2",
    /// invented in `ReportExporter`. Fails if any invented value returns.
    func testReportOmitsTimingsBitMatchDoesNotMeasure() async throws {
        try await FileOperationsTestLock.shared.run {
            let fixture = try DisposableTransferFixture(seed: 20_260_926, fileCount: 3, bytesPerFile: 16 * 1024)
            defer { fixture.cleanup() }
            let executor = CopyVerifyExecutor(
                platformManager: MacOSPlatformManager.shared,
                timingService: OperationTimingService(),
                errorService: ErrorReportingService(),
                stateService: OperationStateService(),
                backgroundTaskService: IOSBackgroundTaskService.shared
            )
            let config = CopyVerifyConfig(
                operationId: UUID(), sourceURL: fixture.source, destinationURLs: fixture.destinations,
                verificationMode: .standard, cameraLabelSettings: CameraLabelSettings(),
                reportSettings: ReportPrefs(makeReport: true), estimatedFiles: fixture.manifest.count,
                estimatedBytes: 0, currentMode: .copyAndVerify
            )
            _ = try await executor.execute(config: config, callbacks: CopyVerifyCallbacks(
                onProgress: { _ in }, onResult: { _ in }, onStateChange: { _ in }, onAuthoritativeResults: { _ in }
            ))

            let reports = fixture.destinations[0].appendingPathComponent("Reports", isDirectory: true)
            let jsonURL = try XCTUnwrap(try FileManager.default
                .contentsOfDirectory(at: reports, includingPropertiesForKeys: nil)
                .first { $0.pathExtension == "json" })
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any])
            let performance = try XCTUnwrap(object["performance"] as? [String: Any])
            for key in ["copyDuration", "verifyDuration", "peakSpeedMBps"] {
                XCTAssertTrue(performance[key] == nil || performance[key] is NSNull, "performance.\(key) is invented: \(String(describing: performance[key]))")
            }
            XCTAssertNotNil(performance["totalDuration"] as? NSNumber, "the measured total stays")
            let destinations = try XCTUnwrap(object["destinations"] as? [[String: Any]])
            for destination in destinations {
                for key in ["copyDuration", "verifyDuration"] {
                    XCTAssertTrue(destination[key] == nil || destination[key] is NSNull, "destinations.\(key) is invented")
                }
            }
        }
    }
}
