// TransferFinishNotice.swift - What the "transfer finished" notification says.
import Foundation
import BitMatchEngine

/// The notification sent when a transfer ends while BitMatch is in the
/// background. Only a real success says the card is safe to erase
/// (Promise 2).
struct TransferFinishNotice: Equatable, Sendable {
    let title: String
    let body: String

    /// `nil` for a cancelled or never-started transfer: nothing to report.
    static func make(
        state: OperationState,
        sourceName: String,
        backupCount: Int,
        issueCount: Int,
        mode: VerificationMode
    ) -> TransferFinishNotice? {
        let card = sourceName.isEmpty ? "The card" : sourceName
        let backups = backupCount == 1 ? "1 backup" : "\(backupCount) backups"
        switch state {
        case .completed(let info) where info.success:
            return .init(title: "\(card) is safe to erase",
                         body: "Copied to \(backups) and verified.")
        case .completed where issueCount > 0:
            let files = issueCount == 1 ? "1 file" : "\(issueCount) files"
            return .init(title: "\(card) needs attention",
                         body: "\(files) had problems. Open BitMatch to review.")
        case .completed where mode == .quick:
            return .init(title: "\(card) copied, not verified",
                         body: "Quick mode only compared file sizes. Keep the card until it is verified.")
        case .completed:
            return .init(title: "\(card) needs attention",
                         body: "The copy finished but was not fully confirmed. Open BitMatch to review.")
        case .failed:
            return .init(title: "\(card) transfer failed",
                         body: "Open BitMatch to see what went wrong.")
        default:
            return nil
        }
    }
}
