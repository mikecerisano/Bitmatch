// Views/MasterReport/Components/MasterReportTransfersView.swift
import SwiftUI

struct MasterReportTransfersView: View {
    let foundTransfers: [TransferCard]
    @Binding var selectedTransfers: Set<UUID>
    @Binding var productionNotes: String
    let onGenerateReport: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            transfersHeaderCard
            transfersScrollView
            notesCard
            generateReportButton
        }
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private var transfersHeaderCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Today's Transfers")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Summary stats
                HStack(spacing: 32) {
                    StatView(title: "Total Size", value: formatBytes(totalSize), color: .blue)
                    StatView(title: "Total Files", value: "\(totalFiles)", color: .green)
                    StatView(title: "Cameras", value: "\(uniqueCameras)", color: .orange)
                    StatView(
                        title: "Verified",
                        value: "\(verifiedCount)/\(foundTransfers.count)",
                        color: verifiedCount == foundTransfers.count ? .green : .orange
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var transfersScrollView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(groupedTransfers, id: \.key) { camera, transfers in
                    CameraGroupView(
                        camera: camera,
                        transfers: transfers,
                        selectedTransfers: $selectedTransfers
                    )
                }
            }
        }
        .frame(maxHeight: 400)
    }
    
    @ViewBuilder
    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Production Notes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                TextEditor(text: $productionNotes)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                
                Text("Optional: Add notes for post-production team")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
    
    @ViewBuilder
    private var generateReportButton: some View {
        HStack {
            Spacer()
            
            Button {
                onGenerateReport()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                    Text("Generate Master Report")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selectedTransfers.isEmpty ? Color.gray : Color.green)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedTransfers.isEmpty)
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var groupedTransfers: [(key: String, value: [TransferCard])] {
        Dictionary(grouping: foundTransfers) { transfer in
            transfer.cameraName
        }
        .sorted { $0.key < $1.key }
    }
    
    private var totalSize: Int64 {
        foundTransfers.reduce(0) { $0 + $1.totalSize }
    }
    
    private var totalFiles: Int {
        foundTransfers.reduce(0) { $0 + $1.fileCount }
    }
    
    private var uniqueCameras: Int {
        Set(foundTransfers.map { $0.cameraName }).count
    }
    
    private var verifiedCount: Int {
        foundTransfers.filter { $0.verified }.count
    }
    
    // MARK: - Helper Methods
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}