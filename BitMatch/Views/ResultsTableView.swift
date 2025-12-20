import SwiftUI

struct ResultsTableView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var showOnlyIssues: Bool
    @State private var scrollToBottom = false
    // Removed caching @State to avoid mutating state during view updates
    
    // Convenience accessors
    private var progress: ProgressViewModel { coordinator.progressViewModel }
    private var results: [ResultRow] { coordinator.results }
    
    private var issueCount: Int {
        results.filter { !($0.status.contains("✅") || $0.status.contains("Match")) }.count
    }
    
    // Compute filtered results (pure; no state mutation during render)
    private var filteredResults: [ResultRow] {
        let allResults = showOnlyIssues
            ? results.filter { !($0.status.contains("✅") || $0.status.contains("Match")) }
            : results
        // Limit visible results for performance
        let maxVisible = 1000
        if allResults.count > maxVisible {
            // Show most recent results plus all issues
            let issues = allResults.filter { !($0.status.contains("✅") || $0.status.contains("Match")) }
            let recentMatches = allResults.filter { $0.status.contains("✅") || $0.status.contains("Match") }.suffix(maxVisible - issues.count)
            return issues + Array(recentMatches)
        } else {
            return allResults
        }
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
    }
    
    @ViewBuilder
    private var statsHeader: some View {
        HStack {
            // File counts
            HStack(spacing: 12) {
                fileCountView
                matchCountView
                if issueCount > 0 {
                    issueCountView
                }
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
            
            Spacer()
            
            // Speed indicator when verifying
            if coordinator.isOperationInProgress {
                HStack(spacing: 12) {
                    if progress.filesPerSecond > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 10))
                            Text(formatSpeed())
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                    
                    if let remaining = progress.estimatedTimeRemaining {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(formatTime(remaining))
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            
            // Control buttons
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
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
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green.opacity(0.5))
                        
                        Text("No issues found")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        if progress.matchCount > 0 {
                            Text("All \(progress.matchCount) files verified successfully")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else if filteredResults.isEmpty {
                    // Empty state when no results at all
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text("No results yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            (row.status.contains("✅") || row.status.contains("Match")) ?
            Color.clear :
            statusColor(for: row.status).opacity(0.1)
        )
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
        if status.contains("✅") || status.contains("Match") {
            return "checkmark.circle"
        } else if status.contains("❌") || status.contains("Error") || status.contains("Failed") {
            return "xmark.circle"
        } else if status.contains("⚠️") || status.contains("Warning") || status.contains("Missing") {
            return "exclamationmark.triangle"
        } else if status.contains("🔄") || status.contains("Processing") || status.contains("Copying") {
            return "arrow.clockwise"
        } else {
            return "questionmark.circle"
        }
    }
    
    private func statusColor(for status: String) -> Color {
        if status.contains("✅") || status.contains("Match") {
            return .green
        } else if status.contains("❌") || status.contains("Error") || status.contains("Failed") {
            return .red
        } else if status.contains("⚠️") || status.contains("Warning") || status.contains("Missing") {
            return .yellow
        } else if status.contains("🔄") || status.contains("Processing") || status.contains("Copying") {
            return .blue
        } else {
            return .gray
        }
    }
}
