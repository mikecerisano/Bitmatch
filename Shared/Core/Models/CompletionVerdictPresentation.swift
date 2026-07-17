import Foundation

struct CompletionVerdictPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    let sourceGuidance: String?

    static func make(_ verdict: CompletionVerdict) -> Self {
        switch verdict {
        case .success:
            return Self(
                title: "Transfer complete",
                detail: "Every reported file has a verified result.",
                symbol: "checkmark.circle.fill",
                sourceGuidance: nil
            )
        case .issues:
            return Self(
                title: "Review required",
                detail: "Some files need attention before this transfer can be treated as safe.",
                symbol: "exclamationmark.triangle.fill",
                sourceGuidance: "Review failed files before clearing source media."
            )
        case .failed:
            return Self(
                title: "Transfer failed",
                detail: "No safe completion verdict was recorded.",
                symbol: "xmark.circle.fill",
                sourceGuidance: "Keep source media intact and review the transfer evidence."
            )
        }
    }
}
