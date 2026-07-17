import CoreGraphics

enum MasterReportLayoutPresentation: Equatable {
    case horizontal
    case compactGrid
}

enum MasterReportLayoutPolicy {
    static let horizontalThreshold: CGFloat = 640

    static func presentation(for availableWidth: CGFloat) -> MasterReportLayoutPresentation {
        availableWidth >= horizontalThreshold ? .horizontal : .compactGrid
    }
}
