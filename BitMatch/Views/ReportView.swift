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

    private static let mediaExtensions: Set<String> = [
        "MOV", "MP4", "M4V", "MXF", "R3D", "BRAW", "MPG", "MPEG", "AVI", "WMV",
        "ARW", "CR2", "CR3", "NEF", "RAF", "RW2", "DNG", "RAW", "SR2", "ORF",
        "JPG", "JPEG", "PNG", "TIFF", "TIF", "BMP", "HEIC", "HEIF", "GIF",
        "WAV", "AIFF", "AIF", "MP3", "AAC", "FLAC", "M4A"
    ]
    
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
    
    private var totalDurationSeconds: TimeInterval {
        max(0, s.finished.timeIntervalSince(s.started))
    }
    
    private var filesPerSecond: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return Double(rows.count) / totalDurationSeconds
    }
    
    private var averageFileSize: String {
        guard !rows.isEmpty else { return "—" }
        let totalBytes = rows.reduce(into: Int64(0)) { $0 += $1.size }
        let average = totalBytes / Int64(rows.count)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: average)
    }
    
    private var largestFile: ResultRow? {
        rows.max(by: { $0.size < $1.size })
    }
    
    private var smallestFile: ResultRow? {
        rows.min(by: { $0.size < $1.size })
    }
    
    private var extensionBreakdown: [(ext: String, count: Int)] {
        let grouped = Dictionary(grouping: rows) { row -> String in
            let ext = URL(fileURLWithPath: row.path).pathExtension.uppercased()
            return ext.isEmpty ? "—" : ext
        }
        let ranked: [(ext: String, count: Int)] = grouped
            .map { (ext: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.ext < rhs.ext
                }
                return lhs.count > rhs.count
            }
        return Array(ranked.prefix(5))
    }
    
    private var manifestPreview: [ResultRow] {
        ResultPresentation.mediaRows(rows, allowedExtensions: Self.mediaExtensions)
    }

    private var integritySummary: ResultIntegritySummary {
        ResultIntegritySummary(rows: rows)
    }
    
    private var verifiedFileCount: Int {
        integritySummary.successfulRows.count
    }
    
    private var issueCount: Int {
        integritySummary.issueRows.count
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
            
            // Performance Metrics
            metricsSection
            
            Divider().padding(.vertical, 12)
            
            environmentSection
            
            Divider().padding(.vertical, 12)
            
            // Technical Details
            technicalSection
            
            Divider().padding(.vertical, 12)
            
            // File Statistics
            statisticsSection
            
            if !extensionBreakdown.isEmpty {
                Divider().padding(.vertical, 12)
                extensionSection
            }
            
            Divider().padding(.vertical, 12)
            manifestSection
            
            // Issues Detail (if any)
            if issueCount > 0 {
                Divider().padding(.vertical, 12)
                issuesSection
            }
            
            // Success Badge or Issues Summary
            Spacer(minLength: 20)
            
            if issueCount == 0 {
                successBadge
            } else {
                issuesSummaryTable
            }
            
            Spacer(minLength: 0)
            
            // Footer
            Divider()
            footerSection
        }
        .padding(.top, 20)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
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
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance Metrics")
                .font(.system(size: 14, weight: .semibold))
            
            HStack(spacing: 40) {
                StatBox(title: "Average File Size", value: averageFileSize, color: .blue)
                StatBox(title: "Files / Second",
                        value: filesPerSecond > 0 ? String(format: "%.1f", filesPerSecond) : "—",
                        color: .purple)
                StatBox(title: "Largest File",
                        value: formattedFileSize(largestFile),
                        color: .indigo)
                StatBox(title: "Smallest File",
                        value: formattedFileSize(smallestFile),
                        color: .teal)
            }
        }
    }
    
    @ViewBuilder
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Environment & Operator")
                .font(.system(size: 14, weight: .semibold))
            
            Grid(horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    environmentLabel("Client", value: s.client)
                    environmentLabel("Company", value: s.company)
                }
                GridRow {
                    environmentLabel("App Version", value: s.appVersion)
                    environmentLabel("OS Version", value: s.osVersion)
                }
                GridRow {
                    environmentLabel("Verification", value: s.verificationMethod)
                    environmentLabel("Workers", value: "\(s.workers) parallel")
                }
            }
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
                StatBox(title: "Files", value: "\(rows.count)", color: .blue)
                StatBox(title: "Matched", value: "\(verifiedFileCount)", color: .green)
                StatBox(title: "Issues", value: "\(issueCount)", color: issueCount > 0 ? .orange : .gray)
                StatBox(title: "Success Rate",
                       value: String(format: "%.1f%%", rows.isEmpty ? 100 : (Double(verifiedFileCount) / Double(rows.count) * 100)),
                       color: issueCount == 0 ? .green : .orange)
            }
        }
    }
    
    @ViewBuilder
    private var extensionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top File Types")
                .font(.system(size: 14, weight: .semibold))
            
            HStack(spacing: 12) {
                ForEach(extensionBreakdown, id: \.ext) { item in
                    StatChip(label: item.ext, value: "\(item.count)")
                }
            }
        }
    }
    
    @ViewBuilder
    private var manifestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Media Files Transferred")
                .font(.system(size: 14, weight: .semibold))
            
            if manifestPreview.isEmpty {
                Text("No media files detected in this run.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    manifestHeaderRow
                    Divider()
                    ForEach(manifestPreview, id: \.id) { row in
                        manifestDataRow(for: row)
                        if row.id != manifestPreview.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.03))
                        )
                )
            }
            
        }
    }
    
    @ViewBuilder
    private var manifestHeaderRow: some View {
        HStack(spacing: 12) {
            Text("Status")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text("File")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 150, alignment: .leading)
            Text("Source")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 140, alignment: .leading)
            Text("Destination")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 140, alignment: .leading)
            Text("Size")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 65, alignment: .trailing)
        }
        .foregroundColor(.secondary)
        .padding(.vertical, 6)
    }
    
    private func manifestDataRow(for row: ResultRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol(for: row.status))
                .foregroundColor(statusColor(for: row.status))
                .font(.system(size: 10))
                .frame(width: 44, alignment: .leading)
            Text(row.fileName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
            Text(shortDirectoryPath(for: row.path))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 140, alignment: .leading)
            Text(destinationDisplay(for: row))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 140, alignment: .leading)
            Text(row.formattedSize)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Issues Detail (\(issueCount))")
                .font(.system(size: 14, weight: .semibold))
            
            let groups = ResultPresentation.issueGroups(rows)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: statusSymbol(for: group.status))
                                .foregroundColor(statusColor(for: group.status))
                                .font(.system(size: 10))
                            Text("\(group.status) (\(group.rows.count))")
                                .font(.system(size: 11, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(group.rows.prefix(10), id: \.id) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.fileName)
                                        .font(.system(size: 10, weight: .medium))
                                    Text("Source: \(shortDirectoryPath(for: row.path))")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    let destination = destinationDisplay(for: row)
                                    if destination != "—" {
                                        Text("Destination: \(destination)")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    if let checksum = row.checksum, !checksum.isEmpty {
                                        Text("Checksum: \(checksum.prefix(16))…")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            if group.rows.count > 10 {
                                Text("Showing 10 of \(group.rows.count) files; \(group.rows.count - 10) more in the complete result manifest.")
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
            summaryTableHeader
            summaryTableContent
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
    
    // MARK: - Summary Table Components
    
    @ViewBuilder
    private var summaryTableHeader: some View {
        Text("Issues Summary (\(issueCount))")
            .font(.system(size: 12, weight: .semibold))
    }
    
    @ViewBuilder
    private var summaryTableContent: some View {
        let groups = ResultPresentation.issueGroups(rows)
        
        VStack(spacing: 2) {
            ForEach(groups) { group in
                summaryTableRow(for: group.status, count: group.rows.count)
            }
        }
    }
    
    @ViewBuilder
    private func summaryTableRow(for status: String, count: Int) -> some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: statusSymbol(for: status))
                    .font(.system(size: 10))
                Text(status)
                    .font(.system(size: 10))
            }
            .foregroundColor(statusColor(for: status))
            
            Spacer()
            
            Text("\(count) files")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(statusColor(for: status).opacity(0.1))
        )
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

private struct StatChip: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.12))
                )
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

private func formattedFileSize(_ row: ResultRow?) -> String {
    guard let row else { return "—" }
    return ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)
}

@ViewBuilder
private func environmentLabel(_ title: String, value: String) -> some View {
    HStack(spacing: 6) {
        Text("\(title):")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .frame(width: 80, alignment: .trailing)
        Text(value.isEmpty ? "—" : value)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

private extension ReportView {
    func shortDirectoryPath(for path: String, components: Int = 3) -> String {
        var url = URL(fileURLWithPath: path)
        if !url.pathExtension.isEmpty {
            url.deleteLastPathComponent()
        }
        var segments = url.pathComponents.filter { $0 != "/" }
        if segments.isEmpty {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        if segments.count > components {
            segments = Array(segments.suffix(components))
        }
        return segments.joined(separator: "/")
    }
    
    func destinationDisplay(for row: ResultRow) -> String {
        if let destinationPath = row.destinationPath, !destinationPath.isEmpty {
            return shortDirectoryPath(for: destinationPath)
        }
        if let destination = row.destination, !destination.isEmpty {
            return destination
        }
        if let fallback = s.destinations.first {
            return shortDirectoryPath(for: fallback)
        }
        return "—"
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
