// SharedCompareFlowTests.swift
import Foundation
import Testing
@testable import BitMatch

struct SharedCompareFlowTests {

    @Test
    func testCompareFoldersCompletes() async throws {
        #if os(macOS)
        // Arrange: create two small folders with overlapping and unique files
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let left = tmp.appendingPathComponent("bitmatch_cmp_left_\(UUID().uuidString)")
        let right = tmp.appendingPathComponent("bitmatch_cmp_right_\(UUID().uuidString)")
        try fm.createDirectory(at: left, withIntermediateDirectories: true)
        try fm.createDirectory(at: right, withIntermediateDirectories: true)

        // Files: A in both (different contents), B only left, C only right
        try Data("A".utf8).write(to: left.appendingPathComponent("A.txt"))
        try Data("B".utf8).write(to: left.appendingPathComponent("B.txt"))
        try Data("X".utf8).write(to: right.appendingPathComponent("A.txt"))
        try Data("C".utf8).write(to: right.appendingPathComponent("C.txt"))

        // Act: drive compare via SharedAppCoordinator
        let coordinator = await MainActor.run { SharedAppCoordinator(platformManager: MacOSPlatformManager.shared) }
        await MainActor.run {
            coordinator.currentMode = .compareFolders
            coordinator.verificationMode = .standard
            coordinator.leftURL = left
            coordinator.rightURL = right
        }
        await coordinator.compareFolders()

        // Assert: operation completes successfully
        let statsAndState = await MainActor.run { () -> (CompareStats?, Bool) in
            let completed: Bool
            if case .completed = coordinator.operationState { completed = true } else { completed = false }
            return (coordinator.lastCompareStats, completed)
        }
        #expect(statsAndState.1)
        // Validate counts: common=0, onlyLeft=1 (B), onlyRight=1 (C), mismatched=1 (A)
        #expect(statsAndState.0?.commonCount == 0)
        #expect(statsAndState.0?.onlyInLeftCount == 1)
        #expect(statsAndState.0?.onlyInRightCount == 1)
        #expect(statsAndState.0?.mismatchedCount == 1)

        // Cleanup
        try? fm.removeItem(at: left)
        try? fm.removeItem(at: right)
        #else
        #expect(true)
        #endif
    }
}
