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

struct ResultIssueGroup: Identifiable {
    let status: String
    let rows: [ResultRow]

    var id: String { status }
}

struct ReportResultStatistics {
    let totalFiles: Int
    let totalBytes: Int64
    let averageFileSizeBytes: Int64?
    let largestFile: ResultRow?
    let smallestFile: ResultRow?
    let extensionCounts: [String: Int]

    init(rows: [ResultRow]) {
        totalFiles = rows.count
        totalBytes = rows.reduce(into: Int64(0)) { total, row in
            let (sum, overflow) = total.addingReportingOverflow(max(0, row.size))
            total = overflow ? .max : sum
        }
        averageFileSizeBytes = rows.isEmpty ? nil : totalBytes / Int64(rows.count)
        largestFile = rows.max { $0.size < $1.size }
        smallestFile = rows.min { $0.size < $1.size }
        extensionCounts = Dictionary(grouping: rows) { row in
            let fileExtension = URL(fileURLWithPath: row.path).pathExtension.uppercased()
            return fileExtension.isEmpty ? "—" : fileExtension
        }.mapValues(\.count)
    }

    func filesPerSecond(duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return Double(totalFiles) / duration
    }

    func extensionBreakdown(limit: Int) -> [(ext: String, count: Int)] {
        guard limit > 0 else { return [] }
        let counts: [(ext: String, count: Int)] = extensionCounts.map {
            (ext: $0.key, count: $0.value)
        }
        let ranked = counts.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.ext < rhs.ext : lhs.count > rhs.count
        }
        return Array(ranked.prefix(limit))
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

        // Green means verified (Promise 2): a row that was copied but never
        // checksum- or byte-verified keeps the run out of success, whatever
        // the run itself reported.
        if rows.contains(where: { ResultOutcome(statusText: $0.status) == .copiedUnverified }) {
            return .issues
        }

        return .success
    }
}

enum ResultPresentation {
    static func mediaRows(
        _ rows: [ResultRow],
        allowedExtensions: Set<String>
    ) -> [ResultRow] {
        let normalizedExtensions = Set(allowedExtensions.map { $0.uppercased() })
        return rows.filter { row in
            let fileExtension = URL(fileURLWithPath: row.path).pathExtension.uppercased()
            return !fileExtension.isEmpty && normalizedExtensions.contains(fileExtension)
        }
    }

    static func issueGroups(_ rows: [ResultRow]) -> [ResultIssueGroup] {
        let issues = ResultIntegritySummary(rows: rows).issueRows
        return Dictionary(grouping: issues, by: \.status)
            .map { ResultIssueGroup(status: $0.key, rows: $0.value) }
            .sorted { $0.status < $1.status }
    }

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

/// Summaries describe retained result evidence, never infer completion from an empty list.
struct DestinationResultSummary: Identifiable {
    let id: String
    let title: String
    let rows: [ResultRow]

    var issueCount: Int { rows.filter { !$0.isSuccessStatus }.count }
    var unverifiedCount: Int { rows.filter { $0.isSuccessStatus && ($0.checksum?.isEmpty != false || $0.status.contains("Copied")) }.count }
    var needsAttention: Bool { rows.isEmpty || issueCount > 0 || unverifiedCount > 0 }
    var detail: String {
        guard !rows.isEmpty else { return "No file results recorded" }
        if issueCount > 0 { return "\(issueCount) of \(rows.count) reported results need attention" }
        if unverifiedCount > 0 { return "\(unverifiedCount) of \(rows.count) file results are unverified" }
        return rows.count == 1 ? "1 verified file result" : "\(rows.count) verified file results"
    }

    static func make(rows: [ResultRow], destinations: [URL]) -> [Self] {
        let roots = destinations.sorted { $0.path.count > $1.path.count }
        var assigned: [String: [ResultRow]] = [:]
        var remaining: [ResultRow] = []
        for row in rows {
            if let path = row.destinationPath,
               let root = roots.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
                assigned[root.path, default: []].append(row)
            } else {
                remaining.append(row)
            }
        }
        var summaries = destinations.map { root in
            Self(id: root.path, title: root.lastPathComponent, rows: assigned[root.path] ?? [])
        }
        let groups = Dictionary(grouping: remaining) { $0.destination ?? "Other results" }
        summaries += groups.keys.sorted().map { name in
            Self(id: "reported:" + name, title: name, rows: groups[name] ?? [])
        }
        return summaries
    }
}
