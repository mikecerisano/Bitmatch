// CompletionSummaryView.swift - Operation completion summary component for iPad
import SwiftUI
import UniformTypeIdentifiers

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
            
            VStack(alignment: .leading, spacing: 14) {
                ForEach(DestinationResultSummary.make(rows: coordinator.results, destinations: coordinator.destinationURLs)) { summary in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: summary.needsAttention ? "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundColor(summary.needsAttention ? .orange : .green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.title).font(.headline)
                            Text(summary.detail).font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                DisclosureGroup("File details") {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(ResultPresentation.visibleRows(coordinator.results, issuesOnly: false, limit: 1_000)) { row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.fileName).font(.subheadline).lineLimit(2)
                                Text([row.destination, row.status].compactMap { $0 }.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundColor(row.isSuccessStatus ? Color.secondary : Color.orange)
                            }
                        }
                        if coordinator.results.count > 1_000 {
                            Text("Showing 1,000 retained results. Export a report for the full record.")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.vertical, 8)
                DisclosureGroup("Transfer details") {
                    OperationSummaryStatsView(coordinator: coordinator)
                }
                .padding(.vertical, 8)
            }
            
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
        CompletionVerdictPresentation.make(
            state: coordinator.operationState,
            rows: coordinator.results,
            hasErrors: coordinator.hasErrors,
            hasCriticalErrors: coordinator.hasCriticalErrors
        )
    }

    private var statusColor: Color {
        switch verdict {
        case .success: .green
        case .issues: .orange
        case .failed: .red
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(statusColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title).font(.title2.weight(.semibold))
                Text(presentation.detail).font(.subheadline).foregroundColor(.secondary)
                if let duration = coordinator.operationDuration {
                    Text("Completed in \(duration)").font(.footnote).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                
                Text(CompletionVerdictPresentation.make(
                    state: coordinator.operationState,
                    rows: coordinator.results,
                    hasErrors: coordinator.hasErrors,
                    hasCriticalErrors: coordinator.hasCriticalErrors
                ).sourceGuidance ?? "Review transfer evidence before clearing source media.")
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
    @State private var exportDocument: TransferHistoryDocument?
    @State private var showExport = false
    @State private var exportType = UTType.json
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Menu {
                Button("JSON report") { export(asCSV: false) }
                Button("CSV results") { export(asCSV: true) }
            } label: {
                Label("Export report", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button {
                coordinator.resetForNewOperation()
                coordinator.sourceURL = nil
                coordinator.destinationURLs = []
            } label: {
                Label("New transfer", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .disabled(coordinator.isOperationInProgress)
        .fileExporter(
            isPresented: $showExport,
            document: exportDocument,
            contentType: exportType,
            defaultFilename: "BitMatch-transfer"
        ) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
    }

    private func export(asCSV: Bool) {
        do {
            exportDocument = try coordinator.completionExportDocument(asCSV: asCSV)
            exportType = asCSV ? .commaSeparatedText : .json
            errorMessage = nil
            showExport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
