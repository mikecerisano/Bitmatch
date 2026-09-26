import CoreGraphics

enum WindowPresentationPolicy {
    static let allowsManualResizing = true
    static let initialWidth: CGFloat = 680
    static let initialHeight: CGFloat = 650
    static let minimumWidth: CGFloat = 580
    static let minimumHeight: CGFloat = 550
    static let maximumWidth: CGFloat = 1440
    static let maximumHeight: CGFloat = 1000

    static func shouldCenterWindow(hasSavedPlacement: Bool, isInterfaceLab: Bool) -> Bool {
        isInterfaceLab || !hasSavedPlacement
    }
}

/// The Mac window's height for each screen (`MacMainView.idealWindowHeight`).
///
/// Each height is the screen's content as laid out at the window's width,
/// plus the window's own parts, so the screen fits without scrolling and
/// without a large empty band. Screens that can grow without limit (a long
/// file list, many backups) take the tallest allowed height and scroll.
///
/// Widths: the shared screens pick their layout from their own width
/// (`AdaptiveNavigationPolicy`: compact below 600 pt, sidebar from 960 pt).
/// The main scroll view pads 20 pt on each side, and Setup pads another
/// 20 pt, so Setup stacks its boxes below a 680 pt window (the default
/// width) and Progress, Outcome and Master Report go compact below 640 pt.
/// At the 580 pt minimum every screen is compact.
///
/// The numbers are measured from each screen's layout code (fonts at the
/// default size, Mac control heights); see the constants.
enum MacWindowHeightPolicy {
    enum Screen: Equatable {
        case setup(Setup)
        case progress(backups: Int)
        case outcome(backups: Int, needsAttention: Bool)
        case compare(advancedExpanded: Bool)
        case masterReport
    }

    struct Setup: Equatable {
        var hasSource: Bool
        var backups: Int
        /// A warning or blocker banner above Advanced (not the brief
        /// "Analyzing" one, so the window does not bounce while a scan runs).
        var showsProblemBanner: Bool
        var optionsExpanded: Bool
        var connectedDrives: Int = 0
        var showsProjectSetup: Bool
    }

    /// Window header (68) plus the scroll view's top (16) and bottom (20)
    /// padding.
    static let chrome: CGFloat = 104
    /// Setup adds 4 pt above and 8 pt below (`MacSetupView`).
    static let setupChrome: CGFloat = chrome + 12
    /// Gap between sections in every shared screen.
    static let gap: CGFloat = 16

    /// The window height for `screen`, between the window's minimum and the
    /// smaller of its maximum and `available` (the screen's visible height
    /// less room for the menu bar and Dock).
    static func idealHeight(for screen: Screen, windowWidth: CGFloat, available: CGFloat) -> CGFloat {
        let ceiling = max(WindowPresentationPolicy.minimumHeight, min(WindowPresentationPolicy.maximumHeight, available))
        let content = contentHeight(for: screen, windowWidth: windowWidth) ?? ceiling
        return min(max(content, WindowPresentationPolicy.minimumHeight), ceiling)
    }

    /// Nil when the screen should take the tallest allowed height.
    static func contentHeight(for screen: Screen, windowWidth: CGFloat) -> CGFloat? {
        switch screen {
        case .setup(let setup):
            return setupHeight(setup, windowWidth: windowWidth)
        case .progress(let backups):
            return progressHeight(backups: backups, windowWidth: windowWidth)
        case .outcome(let backups, let needsAttention):
            return outcomeHeight(backups: backups, needsAttention: needsAttention, windowWidth: windowWidth)
        case .compare(let advancedExpanded):
            // Unchanged: title 60, the two folder boxes 170, checks and the
            // Compare button 170, on the old 200 pt base. Results scroll.
            return 200 + 60 + 170 + 170 + (advancedExpanded ? 150 : 0)
        case .masterReport:
            // The report model lives inside the shared screen, so one height
            // serves every phase: the tallest state without results ("No
            // reports" at 580 pt: title 80, drive and day 222, notice 108,
            // button 34, gaps 48, chrome 104 = 596) fits with a little room;
            // found transfers scroll below the totals.
            return 620
        }
    }

    // MARK: Setup

    private static func setupHeight(_ setup: Setup, windowWidth: CGFloat) -> CGFloat? {
        // The project form is long and open-ended: take the full height.
        if setup.showsProjectSetup { return nil }
        let sideBySide = windowWidth >= 680
        // Title and one-line subtitle.
        let title: CGFloat = 42
        // Box title (16) + 8, then an empty 120 pt drop box or the chosen
        // folder's card (padding 24, name, path, size: 97).
        let source: CGFloat = 24 + (setup.hasSource ? 97 : 120)
        // Each backup card is 81 pt, 8 apart, then "Add backup…" (8 + 44).
        let backups: CGFloat = setup.backups == 0
            ? 24 + 120
            : 24 + CGFloat(setup.backups) * 81 + CGFloat(setup.backups - 1) * 8 + 52
        // The card around the boxes pads 14 pt.
        let locations: CGFloat = 28 + (sideBySide ? max(source, backups) : source + gap + backups)
        // Two 60 pt workflow choices, side by side or stacked 8 apart.
        let workflow: CGFloat = sideBySide ? 60 : 128
        let banner: CGFloat = setup.showsProblemBanner ? 77 + gap : 0
        // Collapsed Advanced (44 + 24 padding); open adds the label editor
        // and the records options.
        let advanced: CGFloat = 68 + (setup.optionsExpanded ? 330 : 0)
        // Start (34 + 24 padding), plus the line under it once both are
        // chosen (it wraps to two lines when stacked).
        let start: CGFloat = 58 + (setup.hasSource && setup.backups > 0 ? (sideBySide ? 24 : 40) : 0)
        let drives: CGFloat = 12 + 24 + 16 + 8 + (setup.connectedDrives == 0 ? 14 : CGFloat(setup.connectedDrives) * 40 + CGFloat(setup.connectedDrives - 1) * 8)
        return setupChrome + title + locations + drives + workflow + banner + advanced + start + 4 * gap
    }

    // MARK: Progress

    private static func progressHeight(backups: Int, windowWidth: CGFloat) -> CGFloat {
        let width = windowWidth - 40
        let layout = AdaptiveNavigationPolicy.presentation(for: width)
        let backups = max(backups, 1)
        // "Backups" heading (25) and 73 pt rows, 10 apart.
        func backupList(rows: Int) -> CGFloat { 25 + CGFloat(rows) * 73 + CGFloat(rows - 1) * 10 }
        // Live results under the screen: gap, header row (41), and the
        // table's 200 pt minimum; it grows as rows arrive, then scrolls.
        let liveResults: CGFloat = 16 + 241
        let screen: CGFloat
        switch layout {
        case .compact:
            // Header 68 (detail wraps), bar 12, stats in two rows 76,
            // stacked Pause and Cancel 66, current file 16, note 16.
            let fixed: CGFloat = 68 + 12 + 76 + 66 + 16 + 16
            screen = fixed + backupList(rows: backups) + 7 * gap
        case .toolbar:
            // Header 52, bar 12, stats in one row 34, controls 28, file 16,
            // backups in two columns, note 16.
            let fixed: CGFloat = 52 + 12 + 34 + 28 + 16 + 16
            screen = fixed + backupList(rows: (backups + 1) / 2) + 7 * gap
        case .sidebar:
            let run: CGFloat = 52 + 12 + 34 + 28 + 16 + 16 + 80 // 5 gaps
            screen = max(run, backupList(rows: backups))
        }
        return chrome + screen + liveResults
    }

    // MARK: Outcome

    private static func outcomeHeight(backups: Int, needsAttention: Bool, windowWidth: CGFloat) -> CGFloat {
        let width = windowWidth - 40
        let layout = AdaptiveNavigationPolicy.presentation(for: width)
        let backups = max(backups, 1)
        // Backup rows are 65 pt, 12 apart.
        func backupList(rows: Int) -> CGFloat { CGFloat(rows) * 65 + CGFloat(rows - 1) * 12 }
        // The issue lines (76 with the gap) and the file list (300), which opens
        // by itself when something needs attention (Show issues only, a
        // few rows; more scroll).
        let attention: CGFloat = needsAttention ? 376 : 0
        // Transfer details and File details, collapsed.
        let disclosures: CGFloat = 20 + 20
        let screen: CGFloat
        switch layout {
        case .compact:
            // Verdict 130 (title, wrapped detail and guidance, duration);
            // three stacked buttons and the note 130.
            let fixed: CGFloat = 130 + 130
            screen = fixed + backupList(rows: backups) + disclosures + 5 * gap
        case .toolbar:
            // Verdict 100; buttons in a row with the note 54.
            let fixed: CGFloat = 100 + 54
            screen = fixed + backupList(rows: (backups + 1) / 2) + disclosures + 5 * gap
        case .sidebar:
            let verdictColumn: CGFloat = 100 + 54 + 20 + 48 // 3 gaps
            screen = max(verdictColumn, backupList(rows: backups) + gap + 20)
        }
        return chrome + screen + attention
    }
}
