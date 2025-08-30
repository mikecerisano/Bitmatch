import Foundation
import SwiftUI

struct ResultRow: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let target: String?
    var status: Status

    enum Status: String, CaseIterable {
        case match = "Match"
        case missingInDestination = "Missing"
        case extraInDestination = "Extra"
        case sizeMismatch = "Size Mismatch"
        case contentMismatch = "Content Mismatch"
        case readError = "Read Error"
        case copyError = "Copy Error"
    }
}

extension ResultRow.Status {
    var color: Color {
        switch self {
        case .match: return .green
        case .missingInDestination, .contentMismatch, .readError, .copyError: return .red
        case .sizeMismatch: return .orange
        case .extraInDestination: return .yellow
        }
    }
    var symbol: String {
        switch self {
        case .match: return "checkmark.circle.fill"
        case .missingInDestination: return "exclamationmark.triangle.fill"
        case .extraInDestination: return "tray.full.fill"
        case .sizeMismatch: return "arrow.left.and.right.circle.fill"
        case .contentMismatch: return "xmark.octagon.fill"
        case .readError: return "bolt.slash.fill"
        case .copyError: return "doc.text.fill"
        }
    }
    var sortPriority: Int {
        switch self {
        case .contentMismatch, .missingInDestination, .copyError: 0
        case .sizeMismatch: 1
        case .readError: 2
        case .extraInDestination: 3
        case .match: 4
        }
    }
}
