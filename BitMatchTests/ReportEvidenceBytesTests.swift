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
}
