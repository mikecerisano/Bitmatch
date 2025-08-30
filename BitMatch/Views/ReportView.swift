import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ReportView: View {
    struct Summary {
        let jobID: UUID
        let started: Date
        let finished: Date
        let mode: AppMode
        let source: String
        let destinations: [String]
        let totalFiles: Int
        let matched: Int
        let issues: Int
        let workers: Int
        let appVersion: String
        let osVersion: String
        let client: String
        let production: String
        let company: String
        let verificationMethod: String
        let totalBytesProcessed: Int64
        let averageSpeed: Double // MB/s
        let clientLogoData: Data?
        let companyLogoData: Data?
    }

    let s: Summary
    let rows: [ResultRow]
    
    private var duration: String {
        let interval = s.finished.timeIntervalSince(s.started)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "—"
    }
    
    private var throughput: String {
        guard s.averageSpeed > 0 else { return "—" }
        return String(format: "%.1f MB/s", s.averageSpeed)
    }
    
    private var totalSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: s.totalBytesProcessed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with logos
            headerSection
            
            Divider().padding(.vertical, 12)
            
            // Summary Section
            summarySection
            
            Divider().padding(.vertical, 12)
            
            // Technical Details
            technicalSection
            
            Divider().padding(.vertical, 12)
            
            // File Statistics
            statisticsSection
            
            // Issues Detail (if any)
            if s.issues > 0 {
                Divider().padding(.vertical, 12)
                issuesSection
            }
            
            // Success Badge or Issues Summary
            Spacer(minLength: 20)
            
            if s.issues == 0 {
                successBadge
            } else {
                issuesSummaryTable
            }
            
            Spacer(minLength: 0)
            
            // Footer
            Divider()
            footerSection
        }
        .padding(36)
        .frame(width: 612)
        .frame(minHeight: 792) // US Letter height
        .background(Color.white)
    }
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top) {
            // Left side - Report title and date (take up 60% of width)
            VStack(alignment: .leading, spacing: 6) {
                Text("BitMatch Verification Report")
                    .font(.system(size: 24, weight: .bold))
                
                Text(s.finished.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                if !s.client.isEmpty || !s.production.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !s.client.isEmpty {
                            Text("Client: \(s.client)")
                                .font(.system(size: 12, weight: .medium))
                        }
                        if !s.production.isEmpty {
                            Text("Production: \(s.production)")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right side - Logos (PDF-compatible approach)
            VStack(spacing: 10) {
                // Client Logo
                if let clientLogo = s.clientLogoData {
                    #if os(macOS)
                    if let nsImage = NSImage(data: clientLogo) {
                        RepresentableImageView(nsImage: nsImage)
                            .frame(width: 70, height: 50)
                            .clipped()
                    }
                    #else
                    if let uiImage = UIImage(data: clientLogo) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 70, height: 50)
                            .clipped()
                    }
                    #endif
                }
                
                // Company Logo  
                if let companyLogo = s.companyLogoData {
                    #if os(macOS)
                    if let nsImage = NSImage(data: companyLogo) {
                        RepresentableImageView(nsImage: nsImage)
                            .frame(width: 70, height: 50)
                            .clipped()
                    }
                    #else
                    if let uiImage = UIImage(data: companyLogo) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 70, height: 50)
                            .clipped()
                    }
                    #endif
                }
            }
            .frame(width: 100)
        }
    }
    
    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verification Summary")
                .font(.system(size: 14, weight: .semibold))
            
            Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Mode:").foregroundColor(.secondary).font(.system(size: 11))
                    Text(s.mode == .copyAndVerify ? "Copy & Verify" : "Compare Folders")
                        .font(.system(size: 11, weight: .medium))
                    
                    Text("Method:").foregroundColor(.secondary).font(.system(size: 11))
                    Text(s.verificationMethod)
                        .font(.system(size: 11, weight: .medium))
                }
                
                GridRow {
                    Text("Duration:").foregroundColor(.secondary).font(.system(size: 11))
                    Text(duration)
                        .font(.system(size: 11, weight: .medium))
                    
                    Text("Throughput:").foregroundColor(.secondary).font(.system(size: 11))
                    Text(throughput)
                        .font(.system(size: 11, weight: .medium))
                }
                
                GridRow {
                    Text("Total Size:").foregroundColor(.secondary).font(.system(size: 11))
                    Text(totalSizeFormatted)
                        .font(.system(size: 11, weight: .medium))
                    
                    Text("Workers:").foregroundColor(.secondary).font(.system(size: 11))
                    Text("\(s.workers) parallel")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paths")
                .font(.system(size: 14, weight: .semibold))
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text("Source:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Text(s.source)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(2)
                }
                
                ForEach(s.destinations, id: \.self) { dest in
                    HStack(alignment: .top, spacing: 8) {
                        Text("Destination:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        Text(dest)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(2)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Statistics")
                .font(.system(size: 14, weight: .semibold))
            
            HStack(spacing: 40) {
                StatBox(title: "Total Files", value: "\(s.totalFiles)", color: .blue)
                StatBox(title: "Matched", value: "\(s.matched)", color: .green)
                StatBox(title: "Issues", value: "\(s.issues)", color: s.issues > 0 ? .orange : .gray)
                StatBox(title: "Success Rate",
                       value: String(format: "%.1f%%", s.totalFiles > 0 ? (Double(s.matched) / Double(s.totalFiles) * 100) : 100),
                       color: s.issues == 0 ? .green : .orange)
            }
        }
    }
    
    @ViewBuilder
    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Issues Detail (\(s.issues))")
                .font(.system(size: 14, weight: .semibold))
            
            let problems = rows.filter { $0.status != .match }.prefix(100)
            
            // Group issues by type
            let grouped = Dictionary(grouping: problems) { $0.status }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ResultRow.Status.allCases.filter { status in
                    grouped[status] != nil
                }, id: \.self) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: status.symbol)
                                .foregroundColor(status.color)
                                .font(.system(size: 10))
                            Text("\(status.rawValue) (\(grouped[status]?.count ?? 0))")
                                .font(.system(size: 11, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(grouped[status]?.prefix(10) ?? [], id: \.id) { row in
                                Text("• \(row.path)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            if (grouped[status]?.count ?? 0) > 10 {
                                Text("... and \((grouped[status]?.count ?? 0) - 10) more")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var successBadge: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("VERIFICATION SUCCESSFUL")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.green)
                
                Text("All files verified with 100% accuracy")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
            Spacer()
        }
    }
    
    @ViewBuilder
    private var issuesSummaryTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issues Summary")
                .font(.system(size: 12, weight: .semibold))
            
            // Summary table of issues by type
            let grouped = Dictionary(grouping: rows.filter { $0.status != .match }) { $0.status }
            
            VStack(spacing: 2) {
                ForEach(ResultRow.Status.allCases.filter { grouped[$0] != nil }, id: \.self) { status in
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: status.symbol)
                                .font(.system(size: 10))
                            Text(status.rawValue)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(status.color)
                        
                        Spacer()
                        
                        Text("\(grouped[status]?.count ?? 0) files")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(status.color.opacity(0.1))
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private var footerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Job ID: \(s.jobID.uuidString)")
                    .font(.system(size: 8, design: .monospaced))
                
                Text("BitMatch v\(s.appVersion) • \(s.osVersion)")
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary)
            
            Spacer()
            
            if !s.company.isEmpty {
                Text(s.company)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
    }
}

// Platform-specific image view for better PDF compatibility with images
#if os(macOS)
struct RepresentableImageView: NSViewRepresentable {
    let nsImage: NSImage
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = nsImage
    }
}
#endif
