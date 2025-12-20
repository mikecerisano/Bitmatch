// CompletionSummaryView.swift - Operation completion summary component for iPad
import SwiftUI

struct CompletionSummaryView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            // Completion status header
            CompletionStatusHeaderView(coordinator: coordinator)
            
            // Operation summary stats
            OperationSummaryStatsView(coordinator: coordinator)
            
            // Error details (if any)
            if coordinator.hasErrors {
                ErrorDetailsView(coordinator: coordinator)
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
    
    var body: some View {
        VStack(spacing: 12) {
            // Status icon
            Image(systemName: coordinator.hasCriticalErrors ? "xmark.circle.fill" : 
                  coordinator.hasErrors ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(coordinator.hasCriticalErrors ? .red : 
                                coordinator.hasErrors ? .orange : .green)
            
            // Status title
            Text(coordinator.hasCriticalErrors ? "Transfer Failed" : 
                 coordinator.hasErrors ? "Transfer Completed with Issues" : "Transfer Completed Successfully")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Completion time
            if let duration = coordinator.operationDuration {
                Text("Completed in \(duration)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                
                Text("ISSUES SUMMARY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.errorCount > 0 {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        
                        Text("\(coordinator.errorCount) critical errors")
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
                
                Text("Review detailed error log for more information.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(coordinator.hasCriticalErrors ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(coordinator.hasCriticalErrors ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
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