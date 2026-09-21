// FileSelectionFetchTests.swift
import Combine
import Foundation
import Testing
@testable import BitMatch

/// The Mac file-selection folder scan must not run on the main actor, and
/// a rapid reselection must cancel the previous enumeration so its result
/// never publishes over the current selection.
@MainActor
struct FileSelectionFetchTests {
    private func makeDir(withFiles count: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in 0..<count {
            try Data("x".utf8).write(to: dir.appendingPathComponent("f\(index).txt"))
        }
        return dir
    }

    @Test func supersededFetchNeverPublishes() async throws {
        let viewModel = FileSelectionViewModel(enableVolumeMonitoring: false)
        // Slow enough that the first enumeration cannot finish before the
        // reselection lands; small enough to keep the suite fast.
        let first = try makeDir(withFiles: 8_000)
        let second = try makeDir(withFiles: 2)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        var seenCounts: [Int] = []
        var cancellables = Set<AnyCancellable>()
        viewModel.$sourceFolderInfo
            .compactMap { $0?.fileCount }
            .sink { seenCounts.append($0) }
            .store(in: &cancellables)

        viewModel.sourceURL = first
        viewModel.sourceURL = second

        for _ in 0..<300 {
            if viewModel.sourceFolderInfo?.url == second,
               !viewModel.isFetchingSourceInfo { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(viewModel.sourceFolderInfo?.url == second)
        #expect(viewModel.sourceFolderInfo?.fileCount == 2)
        #expect(!seenCounts.contains(8_000))
    }

    private func makeCameraDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("MISC"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("DCIM/f1.jpg"))
        return dir
    }

    @Test func cameraLabelResolvesForCameraStructuredSource() async throws {
        let viewModel = FileSelectionViewModel(enableVolumeMonitoring: false)
        let dir = try makeCameraDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        viewModel.sourceURL = dir

        for _ in 0..<500 {
            if viewModel.sourceCameraLabel != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(viewModel.sourceFolderInfo?.url == dir)
        let label = viewModel.sourceCameraLabel
        #expect(label != nil && !(label?.isEmpty ?? true))
    }

    @Test func supersededCameraHintNeverPublishesStaleLabel() async throws {
        let viewModel = FileSelectionViewModel(enableVolumeMonitoring: false)
        let camDir = try makeCameraDir()
        let plainDir = try makeDir(withFiles: 2)
        defer {
            try? FileManager.default.removeItem(at: camDir)
            try? FileManager.default.removeItem(at: plainDir)
        }

        viewModel.sourceURL = camDir
        viewModel.sourceURL = plainDir

        for _ in 0..<300 {
            if viewModel.sourceFolderInfo?.url == plainDir,
               !viewModel.isFetchingSourceInfo { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(viewModel.sourceFolderInfo?.url == plainDir)
        // Let any superseded hint finish; it must not publish over nil.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(viewModel.sourceCameraLabel == nil)
    }

    @Test func clearingSourceDropsPendingFetch() async throws {
        let viewModel = FileSelectionViewModel(enableVolumeMonitoring: false)
        let dir = try makeDir(withFiles: 8_000)
        defer { try? FileManager.default.removeItem(at: dir) }

        viewModel.sourceURL = dir
        viewModel.sourceURL = nil

        for _ in 0..<300 {
            if !viewModel.isFetchingSourceInfo { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(viewModel.sourceFolderInfo == nil)
        #expect(!viewModel.isFetchingSourceInfo)
        // Let any in-flight scan finish; nothing may republish.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(viewModel.sourceFolderInfo == nil)
    }
}
