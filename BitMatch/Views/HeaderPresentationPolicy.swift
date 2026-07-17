import CoreGraphics

enum HeaderPresentation: Equatable {
    case expanded
    case compact
}

enum HeaderPresentationPolicy {
    /// The full mode strip needs room for title, settings, and three usable targets.
    static let expandedThreshold: CGFloat = 760

    static func presentation(for availableWidth: CGFloat) -> HeaderPresentation {
        availableWidth >= expandedThreshold ? .expanded : .compact
    }
}
