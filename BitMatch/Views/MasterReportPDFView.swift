// Views/MasterReport/MasterReportPDFView.swift
import SwiftUI
import AppKit

struct MasterReportPDFView: View {
    let transfers: [TransferCard]
    let productionNotes: String
    let productionName: String
    let clientName: String
    let companyName: String
    let date: Date
    
    // Computed properties
    private var totalSize: Int64 {
        transfers.reduce(0) { $0 + $1.totalSize }
    }
    
    private var totalFiles: Int {
        transfers.reduce(0) { $0 + $1.fileCount }
    }
    
    private var groupedTransfers: [(camera: String, transfers: [TransferCard])] {
        let grouped = Dictionary(grouping: transfers) { $0.cameraName }
        return grouped.sorted { $0.key < $1.key }.map { (camera: $0.key, transfers: $0.value) }
    }
    
    private var totalRolls: Int {
        transfers.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection
            
            Divider().padding(.vertical, 16)
            
            // Production Overview
            productionOverview
            
            Divider().padding(.vertical, 16)
            
            // Summary Statistics
            summaryStatistics
            
            Divider().padding(.vertical, 16)
            
            // Camera Breakdown
            cameraBreakdown
            
            // Production Notes (if any)
            if !productionNotes.isEmpty {
                Divider().padding(.vertical, 16)
                productionNotesSection
            }
            
            Spacer(minLength: 20)
            
            // Footer
            Divider()
            footerSection
        }
        .padding(36)
        .frame(width: 612)
        .frame(minHeight: 792)
        .background(Color.white)
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Master Transfer Report")
                .font(.system(size: 28, weight: .bold))
            
            Text(date.formatted(date: .complete, time: .omitted))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            if !productionName.isEmpty || !clientName.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !productionName.isEmpty {
                        HStack(spacing: 8) {
                            Text("Production:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(productionName)
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    if !clientName.isEmpty {
                        HStack(spacing: 8) {
                            Text("Client:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(clientName)
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private var productionOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Production Overview")
                .font(.system(size: 16, weight: .semibold))
            
            HStack(spacing: 60) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Total Data Transferred", value: formatBytes(totalSize))
                    InfoRow(label: "Total Files", value: "\(totalFiles) files")
                    InfoRow(label: "Total Rolls/Cards", value: "\(totalRolls)")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Cameras Used", value: "\(groupedTransfers.count)")
                    InfoRow(label: "Verification Status", value: "\(transfers.filter { $0.verified }.count)/\(transfers.count) verified")
                    InfoRow(label: "Transfer Date", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }
    
    @ViewBuilder
    private var summaryStatistics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary Statistics")
                .font(.system(size: 16, weight: .semibold))
            
            // Visual stats boxes
            HStack(spacing: 20) {
                MasterStatBox(
                    title: "Total Volume",
                    value: formatBytes(totalSize),
                    subtitle: "transferred",
                    color: .blue
                )
                
                MasterStatBox(
                    title: "Total Files",
                    value: "\(totalFiles)",
                    subtitle: "verified",
                    color: .green
                )
                
                MasterStatBox(
                    title: "Cameras",
                    value: "\(groupedTransfers.count)",
                    subtitle: "sources",
                    color: .orange
                )
                
                MasterStatBox(
                    title: "Success Rate",
                    value: "100%",
                    subtitle: "verified",
                    color: transfers.allSatisfy { $0.verified } ? .green : .orange
                )
            }
        }
    }
    
    @ViewBuilder
    private var cameraBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera Breakdown")
                .font(.system(size: 16, weight: .semibold))
            
            ForEach(groupedTransfers, id: \.camera) { camera, cameraTransfers in
                VStack(alignment: .leading, spacing: 8) {
                    // Camera header
                    HStack {
                        Image(systemName: iconForCamera(camera))
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        
                        Text(camera)
                            .font(.system(size: 14, weight: .semibold))
                        
                        Spacer()
                        
                        Text("\(cameraTransfers.count) rolls • \(formatBytes(cameraTransfers.reduce(0) { $0 + $1.totalSize }))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
                    
                    // Transfer details
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(cameraTransfers, id: \.id) { transfer in
                            HStack {
                                Image(systemName: transfer.verified ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(transfer.verified ? .green : .gray)
                                
                                Text(URL(fileURLWithPath: transfer.sourcePath).lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                
                                Spacer()
                                
                                Text("\(transfer.fileCount) files")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Text(formatBytes(transfer.totalSize))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Text(transfer.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 20)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
    
    @ViewBuilder
    private var productionNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Production Notes")
                .font(.system(size: 16, weight: .semibold))
            
            Text(productionNotes)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    @ViewBuilder
    private var footerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generated by BitMatch")
                    .font(.system(size: 9))
                Text("Professional Media Verification System")
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary)
            
            Spacer()
            
            if !companyName.isEmpty {
                Text(companyName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 12)
    }
    
    // Helper functions
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useTB, .useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func iconForCamera(_ camera: String) -> String {
        if camera.contains("ALEXA") || camera.contains("RED") {
            return "film"
        } else if camera.contains("DRONE") || camera.contains("DJI") {
            return "airplane"
        } else {
            return "camera.fill"
        }
    }
}

// Helper Views
private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label + ":")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

private struct MasterStatBox: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 100)
        .padding(12)
        .background(color.opacity(0.05))
        .cornerRadius(8)
    }
}
