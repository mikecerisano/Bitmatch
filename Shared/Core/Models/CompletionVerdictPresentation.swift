import Foundation
import BitMatchEngine

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
                sourceGuidance: "Review the results for every destination before clearing source media."
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

    static func make(
        state: OperationState,
        rows: [ResultRow],
        hasErrors: Bool,
        hasCriticalErrors: Bool
    ) -> Self {
        // A cancelled operation keeps its partial results, but it is not
        // an issue state: label it plainly instead of "Review required".
        if state == .cancelled {
            return Self(
                title: "Transfer cancelled",
                detail: "Partial results below are retained. Start a new transfer when ready.",
                symbol: "xmark.circle",
                sourceGuidance: "Keep source media intact until a transfer completes."
            )
        }
        let presentation = make(
            CompletionVerdict.resolve(
                state: state,
                rows: rows,
                hasErrors: hasErrors,
                hasCriticalErrors: hasCriticalErrors
            )
        )
        if case .completed(let info) = state, !info.success {
            return Self(title: presentation.title, detail: info.message, symbol: presentation.symbol,
                        sourceGuidance: "Review results and handoff records before clearing source media.")
        }
        return presentation
    }
}
