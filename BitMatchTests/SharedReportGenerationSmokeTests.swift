// SharedReportGenerationSmokeTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedReportGenerationSmokeTests {

    @Test
    @MainActor
    func testGenerateMasterReportReturnsPDFAndJSON() async throws {
        // Arrange: minimal transfer list
        let sourceInfo = FolderInfo(url: URL(fileURLWithPath: "/tmp/source"), fileCount: 2, totalSize: 1234, lastModified: Date(), isInternalDrive: true)
        let destInfo = FolderInfo(url: URL(fileURLWithPath: "/tmp/dest"), fileCount: 2, totalSize: 1234, lastModified: Date(), isInternalDrive: true)
        let transfer = TransferCard(
            source: sourceInfo,
            destinations: [destInfo],
            cameraCard: nil,
            metadata: nil,
            progress: 1.0,
            state: .completed(OperationCompletionInfo(success: true, message: "ok"))
        )
        let cfg = SharedReportGenerationService.ReportConfiguration.default()
        let service = SharedReportGenerationService()

        // Act
        let result = try await service.generateMasterReport(transfers: [transfer], configuration: cfg)

        // Assert
        #expect(result.pdfData.count > 0)
        #expect(result.jsonData.count > 0)
    }
}
