import CoreGraphics

enum AdaptiveWorkbenchPresentation: Equatable {
    case compact
    case expanded
}

enum AdaptiveWorkbenchLayout {
    /// Nested workbench content is narrower than the window after its safety margins.
    static let expandedThreshold: CGFloat = 600

    static func presentation(for availableWidth: CGFloat) -> AdaptiveWorkbenchPresentation {
        availableWidth >= expandedThreshold ? .expanded : .compact
    }
}
