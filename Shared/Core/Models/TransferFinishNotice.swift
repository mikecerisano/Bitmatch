// TransferFinishNotice.swift - What the "transfer finished" notification says.
import Foundation

/// The notification sent when a transfer ends while BitMatch is in the
/// background. Only a real success says the card is safe to erase
/// (Promise 2).
struct TransferFinishNotice: Equatable, Sendable {
    let title: String
    let body: String
    let kind: TransferNotificationKind

    init(title: String, body: String, kind: TransferNotificationKind) {
        self.title = title
        self.body = body
        self.kind = kind
    }

    /// `nil` for an active or never-started transfer: nothing to report.
    static func make(
        state: OperationState,
        sourceName: String,
        backupNames: [String],
        issueCount: Int,
        kind: TransferNotificationKind
    ) -> TransferFinishNotice? {
        let card = sourceName.isEmpty ? "The card" : sourceName
        let backups = joinedBackupNames(backupNames)
        switch state {
        case .completed(let info) where info.success:
            return .init(title: "\(card) is safe to erase",
                         body: backups.isEmpty ? "Every backup was verified."
                             : "Verified on \(backups).",
                         kind: kind)
        case .completed where issueCount > 0:
            return .init(title: "\(card) needs attention",
                         body: "Do not erase the card.",
                         kind: .attention)
        // Only when Quick was the one gap: a Quick run whose report or
        // project failed still needs attention.
        case .completed(let info) where info.copiedNotVerified:
            return .init(title: "\(card) was copied without checksum verification",
                         body: "Do not erase the card.",
                         kind: kind)
        case .completed:
            return .init(title: "\(card) needs attention",
                         body: "Do not erase the card.",
                         kind: .attention)
        case .failed:
            return .init(title: "\(card) failed",
                         body: "Do not erase the card.",
                         kind: .attention)
        case .cancelled:
            return .init(title: "\(card) was interrupted",
                         body: "Do not erase the card.",
                         kind: .attention)
        default:
            return nil
        }
    }

    static func queueFinished(tally: String) -> TransferFinishNotice {
        .init(title: "Queue finished: \(tally)", body: "", kind: .queueFinished)
    }

    private static func joinedBackupNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.dropLast().joined(separator: ", ")), and \(names[names.count - 1])"
        }
    }
}
