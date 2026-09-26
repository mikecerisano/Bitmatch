import CoreGraphics

enum PreferencesPresentationPolicy {
    static let allowsManualResizing = true
    static let minimumWidth: CGFloat = 580
    static let minimumHeight: CGFloat = 480
    static let initialWidth: CGFloat = 720
    static let initialHeight: CGFloat = 560

    /// The tab bar bug this guards: a tab button used to hit-test only the
    /// pixels its icon and label glyphs actually painted, so clicking the
    /// margin around them did nothing. The fix pairs an explicit `.frame`
    /// of this size with `.contentShape(Rectangle())` on the whole label, so
    /// every point inside the frame — not just the glyphs — is clickable.
    /// These constants exist so the click target and the icon well can be
    /// asserted on: they must be large enough that the icon well fits inside
    /// with room for the caption below it, and never zero (a zero-size frame
    /// would silently reintroduce the bug).
    static let tabWidth: CGFloat = 100
    static let tabHeight: CGFloat = 50
    /// Every tab icon renders in a well of this fixed size, so glyphs with
    /// different natural heights (gear, drive, doc, camera) sit on one
    /// shared baseline instead of drifting per-icon.
    static let tabIconWellSize: CGFloat = 20
}
