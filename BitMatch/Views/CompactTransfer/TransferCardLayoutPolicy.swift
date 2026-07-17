import CoreGraphics

enum TransferCardLayoutPresentation: Equatable {
    case horizontal
    case stacked
}

enum TransferCardLayoutPolicy {
    static let horizontalThreshold: CGFloat = 720

    static func presentation(for availableWidth: CGFloat) -> TransferCardLayoutPresentation {
        availableWidth >= horizontalThreshold ? .horizontal : .stacked
    }
}
