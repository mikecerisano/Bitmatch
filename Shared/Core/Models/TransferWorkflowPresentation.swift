import Foundation

enum TransferWorkflowPresentation: CaseIterable, Equatable, Sendable {
    case quick
    case project

    var title: String {
        switch self {
        case .quick: "Quick transfer"
        case .project: "Project transfer"
        }
    }

    var detail: String {
        switch self {
        case .quick: "Copy, verify, and finish"
        case .project: "Keep card context and off-site evidence"
        }
    }

    var symbol: String {
        switch self {
        case .quick: "bolt.fill"
        case .project: "folder.badge.gearshape"
        }
    }
}
