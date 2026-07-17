import CoreGraphics

enum RemoteDestinationLayoutPresentation: Equatable {
    case twoColumn
    case stacked
}

enum RemoteDestinationLayoutPolicy {
    static let twoColumnThreshold: CGFloat = 520

    static func presentation(for availableWidth: CGFloat) -> RemoteDestinationLayoutPresentation {
        availableWidth >= twoColumnThreshold ? .twoColumn : .stacked
    }
}
