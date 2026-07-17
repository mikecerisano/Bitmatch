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
