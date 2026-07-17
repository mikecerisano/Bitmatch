import CoreGraphics

enum ResultTablePresentation: Equatable {
    case detailed
    case compact
}

enum ResultTableLayoutPolicy {
    static let detailedThreshold: CGFloat = 700

    static func presentation(for availableWidth: CGFloat) -> ResultTablePresentation {
        availableWidth >= detailedThreshold ? .detailed : .compact
    }
}
