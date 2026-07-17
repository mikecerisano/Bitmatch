// CompletionSummaryView.swift - Operation completion summary component for iPad
import SwiftUI

struct CompletionSummaryView: View {
    @ObservedObject var coordinator: SharedAppCoordinator

    private var verdict: CompletionVerdict {
        CompletionVerdict.resolve(
            state: coordinator.operationState,
            rows: coordinator.results,
            hasErrors: coordinator.hasErrors,
            hasCriticalErrors: coordinator.hasCriticalErrors
        )
    }

    private var resultSummary: ResultIntegritySummary {
        ResultIntegritySummary(rows: coordinator.results)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Completion status header
            CompletionStatusHeaderView(coordinator: coordinator, verdict: verdict)
            
            // Operation summary stats
            OperationSummaryStatsView(coordinator: coordinator)
            
            // Issue evidence and field guidance
            if verdict != .success {
                ErrorDetailsView(
                    coordinator: coordinator,
                    verdict: verdict,
                    failedResultCount: resultSummary.issueRows.count
                )
            }
            
            // Action buttons
            CompletionActionButtonsView(coordinator: coordinator)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Completion Status Header

struct CompletionStatusHeaderView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let verdict: CompletionVerdict

    private var presentation: CompletionVerdictPresentation {
        CompletionVerdictPresentation.make(verdict)
    }

    private var statusColor: Color {
        switch verdict {
        case .success: .green
        case .issues: .orange
        case .failed: .red
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Status icon
            Image(systemName: presentation.symbol)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(statusColor)
            
            // Status title
            Text(presentation.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Completion time
            if let duration = coordinator.operationDuration {
                Text("Completed in \(duration)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            Text(presentation.detail)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.68))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Operation Summary Stats

struct OperationSummaryStatsView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 16) {
            Text("OPERATION SUMMARY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .tracking(1.0)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                // Files processed
                SummaryStatCard(
                    icon: "doc.fill",
                    title: "Files Processed",
                    value: "\(coordinator.progress?.filesProcessed ?? 0)",
                    color: .blue
                )
                
                // Average speed
                SummaryStatCard(
                    icon: "speedometer",
                    title: "Avg Speed", 
                    value: coordinator.averageOperationSpeed ?? "N/A",
                    color: .green
                )
                
                // Verification mode
                SummaryStatCard(
                    icon: "checkmark.shield.fill",
                    title: "Verification",
                    value: coordinator.verificationMode.rawValue,
                    color: .purple
                )
                
                // Total size
                if let folderInfo = coordinator.sourceFolderInfo {
                    SummaryStatCard(
                        icon: "externaldrive.fill",
                        title: "Data Copied",
                        value: folderInfo.formattedSize,
                        color: .cyan
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Summary Stat Card

struct SummaryStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Error Details View

struct ErrorDetailsView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let verdict: CompletionVerdict
    let failedResultCount: Int

    private var issueColor: Color {
        verdict == .failed ? .red : .orange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(issueColor)
                
                Text("ISSUES SUMMARY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if failedResultCount > 0 {
                    HStack {
                        Image(systemName: "doc.badge.exclamationmark")
                            .font(.system(size: 12))
                            .foregroundColor(issueColor)

                        Text("\(failedResultCount) failed file \(failedResultCount == 1 ? "result" : "results")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()
                    }
                }

                if coordinator.errorCount > 0 {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        
                        Text("\(coordinator.errorCount) reported \(coordinator.errorCount == 1 ? "error" : "errors")")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                }
                
                if coordinator.warningCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        
                        Text("\(coordinator.warningCount) warnings")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                }
                
                Text(CompletionVerdictPresentation.make(verdict).sourceGuidance ?? "Review transfer evidence before clearing source media.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(issueColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(issueColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Completion Action Buttons

struct CompletionActionButtonsView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            // Primary actions
            HStack(spacing: 12) {
                // Generate Report button
                Button {
                    Task {
                        await coordinator.generateReport()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Generate Report")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(.plain)
                
                // New Transfer button  
                Button {
                    // Reset for new transfer
                    coordinator.sourceURL = nil
                    coordinator.destinationURLs = []
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("New Transfer")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Secondary actions
            HStack(spacing: 12) {
                if coordinator.hasErrors {
                    // View Error Details button
                    Button {
                        // Show error details sheet
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 12, weight: .medium))
                            Text("View Error Details")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Share Results button
                Button {
                    // Share operation results
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                        Text("Share Results")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
