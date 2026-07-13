import Foundation

struct ResultIntegritySummary {
    let successfulRows: [ResultRow]
    let issueRows: [ResultRow]

    init(rows: [ResultRow]) {
        successfulRows = rows.filter(\.isSuccessStatus)
        issueRows = rows.filter { !$0.isSuccessStatus }
    }

    var isSuccessful: Bool {
        issueRows.isEmpty
    }
}

enum CompletionVerdict: Equatable {
    case success
    case issues
    case failed

    static func resolve(
        state: OperationState,
        rows: [ResultRow],
        hasErrors: Bool,
        hasCriticalErrors: Bool
    ) -> CompletionVerdict {
        if hasCriticalErrors || state == .failed {
            return .failed
        }

        let summary = ResultIntegritySummary(rows: rows)
        guard case .completed(let info) = state else {
            return .issues
        }

        if !info.success || !summary.isSuccessful || hasErrors {
            return .issues
        }

        return .success
    }
}

enum ResultPresentation {
    static func visibleRows(
        _ rows: [ResultRow],
        issuesOnly: Bool,
        limit: Int
    ) -> [ResultRow] {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return [] }

        let summary = ResultIntegritySummary(rows: rows)
        let visibleIssues = Array(summary.issueRows.prefix(safeLimit))
        guard !issuesOnly, visibleIssues.count < safeLimit else {
            return visibleIssues
        }

        let remainingCapacity = safeLimit - visibleIssues.count
        let newestSuccesses = summary.successfulRows.suffix(remainingCapacity)
        return visibleIssues + newestSuccesses
    }
}
