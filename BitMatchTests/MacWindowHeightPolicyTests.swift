// MacWindowHeightPolicyTests.swift
import CoreGraphics
import Testing
@testable import BitMatch

/// The Mac window's height per screen. Each test names the one-line bug it
/// catches.
struct MacWindowHeightPolicyTests {
    private typealias Policy = MacWindowHeightPolicy

    private func setup(
        hasSource: Bool = false,
        backups: Int = 0,
        banner: Bool = false,
        expanded: Bool = false,
        project: Bool = false
    ) -> Policy.Screen {
        .setup(Policy.Setup(
            hasSource: hasSource,
            backups: backups,
            showsProblemBanner: banner,
            optionsExpanded: expanded,
            showsProjectSetup: project
        ))
    }

    /// At the 580 pt minimum the source and backup boxes stack, so the
    /// empty Setup needs more height than at the 680 pt default width.
    /// Plant: in `MacWindowHeightPolicy.setupHeight`, change
    /// `windowWidth >= 680` to `windowWidth >= 580`.
    @Test func setupIsTallerWhenItsBoxesStack() {
        let narrow = Policy.idealHeight(for: setup(), windowWidth: 580, available: 2000)
        let standard = Policy.idealHeight(for: setup(), windowWidth: 680, available: 2000)
        #expect(narrow > standard + 150)
    }

    /// Each backup adds a row to Setup.
    /// Plant: in `MacWindowHeightPolicy.setupHeight`, drop
    /// `CGFloat(setup.backups) * 81 +`.
    @Test func setupGrowsWithEachBackup() {
        let one = Policy.idealHeight(for: setup(hasSource: true, backups: 1), windowWidth: 680, available: 2000)
        let three = Policy.idealHeight(for: setup(hasSource: true, backups: 3), windowWidth: 680, available: 2000)
        #expect(three > one + 150)
    }

    @Test func setupMakesRoomForConnectedDrives() {
        let empty = Policy.Setup(hasSource: false, backups: 0, showsProblemBanner: false,
                                 optionsExpanded: false, showsProjectSetup: false)
        var connected = empty
        connected.connectedDrives = 3
        let before = Policy.idealHeight(for: .setup(empty), windowWidth: 680, available: 2000)
        let after = Policy.idealHeight(for: .setup(connected), windowWidth: 680, available: 2000)
        #expect(after > before + 100)
    }

    /// No screen asks for less than the window's minimum or more than the
    /// screen allows.
    /// Plant: in `MacWindowHeightPolicy.idealHeight`, return `content`
    /// without clamping it to `ceiling`.
    @Test func everyHeightStaysWithinTheWindowAndScreen() {
        let screens: [Policy.Screen] = [
            setup(), setup(hasSource: true, backups: 6, banner: true, expanded: true),
            .progress(backups: 1), .progress(backups: 6),
            .outcome(backups: 2, needsAttention: false), .outcome(backups: 6, needsAttention: true),
            .compare(advancedExpanded: true), .masterReport
        ]
        for screen in screens {
            for width in [CGFloat(580), 680, 1100] {
                let height = Policy.idealHeight(for: screen, windowWidth: width, available: 700)
                #expect(height >= WindowPresentationPolicy.minimumHeight)
                #expect(height <= 700)
            }
        }
    }

    /// Project setup is a long form: it takes the tallest allowed height.
    /// Plant: in `MacWindowHeightPolicy.setupHeight`, delete
    /// `if setup.showsProjectSetup { return nil }`.
    @Test func projectSetupTakesTheTallestAllowedHeight() {
        let height = Policy.idealHeight(for: setup(project: true), windowWidth: 680, available: 900)
        #expect(height == 900)
    }

    /// An outcome that needs attention opens its issues and file list, so
    /// the window grows for them.
    /// Plant: in `MacWindowHeightPolicy.outcomeHeight`, set `attention` to 0.
    @Test func outcomeGrowsWhenSomethingNeedsAttention() {
        let clean = Policy.idealHeight(for: .outcome(backups: 2, needsAttention: false), windowWidth: 580, available: 2000)
        let issues = Policy.idealHeight(for: .outcome(backups: 2, needsAttention: true), windowWidth: 580, available: 2000)
        #expect(issues > clean)
    }
}
