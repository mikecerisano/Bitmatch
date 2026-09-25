import Foundation
import Testing
@testable import BitMatch

/// Folder scans run on owned background tasks. A rapid reselection must
/// cancel the previous enumeration and never publish its fast or full
/// results over the current selection.
@MainActor
struct FolderInfoServiceStalenessTests {
    private func makeDir(withFiles count: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in 0..<count {
            try Data("x".utf8).write(to: dir.appendingPathComponent("f\(index).txt"))
        }
        return dir
    }

    @Test func rapidReselectionKeepsLatestSource() async throws {
        let service = FolderInfoService()
        let first = try makeDir(withFiles: 3)
        let second = try makeDir(withFiles: 5)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        await service.updateSource(first)
        await service.updateSource(second)

        // Fast and full results publish in two phases; wait for both.
        await waitUntil {
            service.sourceFolderInfo?.url == second
                && service.folderInfoLoadingState[second] == false
        }
        #expect(service.sourceFolderInfo?.url == second)
        #expect(service.sourceFolderInfo?.fileCount == 5)
        #expect(service.folderInfoLoadingState[second] == false)
    }

    @Test func clearingSourceDropsPendingResults() async throws {
        let service = FolderInfoService()
        let dir = try makeDir(withFiles: 3)
        defer { try? FileManager.default.removeItem(at: dir) }

        await service.updateSource(dir)
        await service.updateSource(nil)
        #expect(service.sourceFolderInfo == nil)

        // Let any in-flight scan finish; nothing may republish.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(service.sourceFolderInfo == nil)
    }
}
