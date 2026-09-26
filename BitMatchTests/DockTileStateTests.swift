// DockTileStateTests.swift
import Testing
@testable import BitMatch
import BitMatchEngine

struct DockTileStateTests {
    /// Promise 2 on the Dock: green only when the transfer succeeded.
    /// Plant: map `.completed` to `.verified` whatever `success` says.
    @Test func onlyASuccessIsGreen() {
        #expect(DockTileState.make(state: .completed(.init(success: true, message: "")), fraction: 1) == .verified)
        #expect(DockTileState.make(state: .completed(.init(success: false, message: "")), fraction: 1) == .needsReview)
        #expect(DockTileState.make(state: .failed, fraction: 0.4) == .failed)
    }

    @Test func runningShowsWholePercentAndIdleShowsTheIcon() {
        #expect(DockTileState.make(state: .copying, fraction: 0.426) == .running(percent: 42))
        #expect(DockTileState.make(state: .verifying, fraction: nil) == .running(percent: 0))
        #expect(DockTileState.make(state: .copying, fraction: 1.7) == .running(percent: 100))
        #expect(DockTileState.make(state: .notStarted, fraction: 0.5) == .appIcon)
        #expect(DockTileState.make(state: .cancelled, fraction: 0.5) == .needsReview)
    }
}
