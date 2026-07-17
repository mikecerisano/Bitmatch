import SwiftUI

struct ResultsTableView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var showOnlyIssues: Bool
    @State private var scrollToBottom = false
    @State private var availableWidth: CGFloat = ResultTableLayoutPolicy.detailedThreshold
    // Removed caching @State to avoid mutating state during view updates
    
    // Convenience accessors
    private var progress: ProgressViewModel { coordinator.progressViewModel }
    private var results: [ResultRow] { coordinator.results }

    private var resultSummary: ResultIntegritySummary {
        ResultIntegritySummary(rows: results)
    }
    
    private var issueCount: Int {
        resultSummary.issueRows.count
    }
    
    // Compute filtered results (pure; no state mutation during render)
    private var filteredResults: [ResultRow] {
        ResultPresentation.visibleRows(results, issuesOnly: showOnlyIssues, limit: 1_000)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter and stats header with cancel button
            statsHeader
            
            Divider()
                .overlay(Color.white.opacity(0.1))
            
            // Results list with proper scrolling
            resultsList
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .frame(maxHeight: 600)  // FIX: Increased from 400 to 600
        .background(widthReader)
    }
    
    @ViewBuilder
    private var statsHeader: some View {
        Group {
            if ResultTableLayoutPolicy.presentation(for: availableWidth) == .detailed {
                detailedStatsHeader
            } else {
                compactStatsHeader
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
    }

    private var detailedStatsHeader: some View {
        HStack {
            resultCounts
            Spacer()
            operationIndicators
            resultControls
        }
    }

    private var compactStatsHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                resultCounts
                Spacer()
                operationIndicators
            }
            HStack {
                Spacer()
                resultControls
            }
        }
    }

    private var resultCounts: some View {
        HStack(spacing: 12) {
            fileCountView
            matchCountView
            if issueCount > 0 { issueCountView }
            if coordinator.progressViewModel.reusedFileCopies > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                    Text("Reused \(coordinator.progressViewModel.reusedFileCopies)")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var operationIndicators: some View {
        if coordinator.isOperationInProgress {
            HStack(spacing: 12) {
                if progress.filesPerSecond > 0 {
                    Label(formatSpeed(), systemImage: "speedometer")
                        .font(.system(size: 11, design: .monospaced))
                }
                if let remaining = progress.estimatedTimeRemaining {
                    Label(formatTime(remaining), systemImage: "clock")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            .foregroundColor(.white.opacity(0.5))
        }
    }

    private var resultControls: some View {
        HStack(spacing: 8) {
                // Cancel button when verifying
                if coordinator.isOperationInProgress {
                    Button {
                        coordinator.cancelOperation()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text("Cancel")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Cancel verification (⌘.)")
                }
                
                // Filter toggle that changes label based on state
                Toggle(isOn: $showOnlyIssues) {
                    Label(showOnlyIssues ? "Show All" : "Issues Only",
                          systemImage: showOnlyIssues ? "list.bullet" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .buttonStyle(CustomButtonStyle())
        }
    }
    
    @ViewBuilder
    private var fileCountView: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text("\(progress.fileCountCompleted)/\(progress.fileCountTotal)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    @ViewBuilder
    private var matchCountView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("\(progress.matchCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.green)
        }
    }
    
    @ViewBuilder
    private var issueCountView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.orange)
                .frame(width: 6, height: 6)
            Text("\(issueCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.orange)
        }
    }
    
    @ViewBuilder
    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if filteredResults.isEmpty && showOnlyIssues {
                    // Empty state when filtering shows no issues
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.green.opacity(0.65))
                        
                        Text("No issues found")
                        .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        if progress.matchCount > 0 {
                            Text("All \(progress.matchCount) files verified successfully")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        Button("Show All Results") {
                            showOnlyIssues = false
                        }
                        .buttonStyle(CustomButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else if filteredResults.isEmpty {
                    // Empty state when no results at all
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text(coordinator.isOperationInProgress ? "Waiting for first results..." : "No results yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))

                        if coordinator.isOperationInProgress {
                            Text("Files will appear here as they are copied and verified.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 2) {
                        // Use LazyVStack for better performance with many items
                        LazyVStack(spacing: 2) {
                            ForEach(filteredResults) { row in
                                resultRow(for: row)
                                    .id(row.id)
                            }
                        }
                        
                        // Show count if results are truncated
                        if results.count > 1000 {
                            HStack {
                                Spacer()
                                Text("Showing \(filteredResults.count) of \(results.count) results")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                Spacer()
                            }
                        }
                        
                        // Auto-scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .onChange(of: filteredResults.count) { oldCount, newCount in
                        // Auto-scroll to bottom when new results are added
                        if newCount > oldCount && coordinator.isOperationInProgress {
                            // Defer to next runloop to avoid state changes during update
                            DispatchQueue.main.async {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 550)  // FIX: Increased from 350 to 550
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
        )
    }
    
    @ViewBuilder
    private func resultRow(for row: ResultRow) -> some View {
        Group {
            if ResultTableLayoutPolicy.presentation(for: availableWidth) == .detailed {
                detailedResultRow(for: row)
            } else {
                compactResultRow(for: row)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            row.isSuccessStatus ? Color.clear : statusColor(for: row.status).opacity(0.1)
        )
    }

    @ViewBuilder
    private func detailedResultRow(for row: ResultRow) -> some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: statusSymbol(for: row.status))
                .font(.system(size: 12))
                .foregroundColor(statusColor(for: row.status))
                .frame(width: 16)

            // File name
            Text(URL(fileURLWithPath: row.path).lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            // File size
            Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 80, alignment: .trailing)

            // Destination drive
            HStack(spacing: 4) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.7))
                Text(row.destination ?? "-")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .trailing)

            // Status text
            Text(row.status)
                .font(.system(size: 10))
                .foregroundColor(statusColor(for: row.status).opacity(0.85))
                .frame(width: 120, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func compactResultRow(for row: ResultRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusSymbol(for: row.status))
                .font(.system(size: 12))
                .foregroundColor(statusColor(for: row.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: row.path).lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file))
                    if let destination = row.destination, !destination.isEmpty {
                        Label(destination, systemImage: "externaldrive.fill")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.54))
            }
            Spacer(minLength: 8)
            Text(row.status)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(statusColor(for: row.status).opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 86, alignment: .trailing)
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in availableWidth = width }
        }
    }
    
    private func formatSpeed() -> String {
        if progress.filesPerSecond >= 1 {
            return String(format: "%.0f files/s", progress.filesPerSecond)
        } else {
            return "Processing..."
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "<1 min"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60)) min"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    // MARK: - Status Helper Methods
    private func statusSymbol(for status: String) -> String {
        let lowercased = status.lowercased()
        if ResultRow.isSuccessStatus(status) {
            return "checkmark.circle"
        } else if status.contains("❌") || lowercased.contains("error") || lowercased.contains("failed") {
            return "xmark.circle"
        } else if status.contains("⚠️") || lowercased.contains("warning") || lowercased.contains("missing") || lowercased.contains("mismatch") {
            return "exclamationmark.triangle"
        } else if status.contains("🔄") || lowercased.contains("processing") || lowercased.contains("copying") {
            return "arrow.clockwise"
        } else {
            return "questionmark.circle"
        }
    }
    
    private func statusColor(for status: String) -> Color {
        let lowercased = status.lowercased()
        if ResultRow.isSuccessStatus(status) {
            return .green
        } else if status.contains("❌") || lowercased.contains("error") || lowercased.contains("failed") {
            return .red
        } else if status.contains("⚠️") || lowercased.contains("warning") || lowercased.contains("missing") || lowercased.contains("mismatch") {
            return .yellow
        } else if status.contains("🔄") || lowercased.contains("processing") || lowercased.contains("copying") {
            return .blue
        } else {
            return .gray
        }
    }
}
