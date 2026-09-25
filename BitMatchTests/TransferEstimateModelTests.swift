import Foundation
import Testing
@testable import BitMatch

@MainActor
struct TransferEstimateModelTests {
    private nonisolated static func estimate(seconds: Double) -> TimeEstimate {
        TimeEstimate(totalSeconds: seconds, copySeconds: seconds, verifySeconds: 0,
                     readSpeedMBps: 100, writeSpeedMBps: 100, destinationCount: 1)
    }

    /// A slow benchmark for an old selection must not replace the estimate
    /// for the current one.
    /// Plant: in `TransferEstimateModel.update`, delete
    /// `current == self.generation` from the guard.
    @Test func staleSlowEstimateNeverOverwritesANewerOne() async {
        let source = URL(fileURLWithPath: "/tmp/card")
        let slow = URL(fileURLWithPath: "/tmp/slow-backup")
        let fast = URL(fileURLWithPath: "/tmp/fast-backup")
        let model = TransferEstimateModel { _, destinations, _, _ in
            if destinations == [slow] {
                try? await Task.sleep(nanoseconds: 300_000_000)
                return Self.estimate(seconds: 999)
            }
            return Self.estimate(seconds: 60)
        }

        model.update(source: source, destinations: [slow], totalBytes: 1_000, mode: .standard)
        model.update(source: source, destinations: [fast], totalBytes: 1_000, mode: .standard)

        #expect(await waitUntil { model.estimate?.totalSeconds == 60 && !model.isCalculating })
        // Let the slow benchmark finish; it must be dropped.
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(model.estimate?.totalSeconds == 60)
        #expect(!model.isCalculating)
    }

    /// Clearing the selection clears the estimate at once, and a benchmark
    /// still running for the old selection cannot bring it back.
    /// Plant: in `TransferEstimateModel.update`, move `generation += 1` below
    /// the early `guard ... else { return }`.
    @Test func clearingTheSelectionDropsAPendingEstimate() async {
        let model = TransferEstimateModel { _, _, _, _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return Self.estimate(seconds: 60)
        }

        model.update(source: URL(fileURLWithPath: "/tmp/card"), destinations: [URL(fileURLWithPath: "/tmp/b")],
                     totalBytes: 1_000, mode: .standard)
        model.update(source: nil, destinations: [], totalBytes: nil, mode: .standard)

        #expect(model.estimate == nil)
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(model.estimate == nil)
        #expect(!model.isCalculating)
    }
}
