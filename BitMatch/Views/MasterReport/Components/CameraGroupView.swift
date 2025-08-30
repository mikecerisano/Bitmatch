// Views/MasterReport/Components/CameraGroupView.swift
import SwiftUI

struct CameraGroupView: View {
    let camera: String
    let transfers: [TransferCard]
    @Binding var selectedTransfers: Set<UUID>
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Camera header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: iconForCamera(camera))
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    Text(camera)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("\(transfers.count) rolls")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    // Select all for this camera
                    Button {
                        toggleCameraSelection(transfers)
                    } label: {
                        Image(systemName: allSelected(transfers) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                            .foregroundColor(allSelected(transfers) ? .green : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            
            // Transfer cards
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(transfers) { transfer in
                        TransferCardView(
                            transfer: transfer,
                            isSelected: Binding(
                                get: { selectedTransfers.contains(transfer.id) },
                                set: { _ in toggleSelection(transfer.id) }
                            )
                        )
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
    }
    
    // MARK: - Helper Methods
    
    private func iconForCamera(_ camera: String) -> String {
        let upper = camera.uppercased()
        
        if upper.contains("ALEXA") || upper.contains("RED") || upper.contains("ARRI") {
            return "film"
        } else if upper.contains("DRONE") || upper.contains("DJI") {
            return "airplane"
        } else if upper.contains("GOPRO") {
            return "video.circle"
        } else if upper.contains("AUDIO") {
            return "waveform"
        } else {
            return "camera.fill"
        }
    }
    
    private func allSelected(_ transfers: [TransferCard]) -> Bool {
        transfers.allSatisfy { selectedTransfers.contains($0.id) }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedTransfers.contains(id) {
            selectedTransfers.remove(id)
        } else {
            selectedTransfers.insert(id)
        }
    }
    
    private func toggleCameraSelection(_ transfers: [TransferCard]) {
        let allSelected = transfers.allSatisfy { selectedTransfers.contains($0.id) }
        
        if allSelected {
            // Deselect all transfers for this camera
            for transfer in transfers {
                selectedTransfers.remove(transfer.id)
            }
        } else {
            // Select all transfers for this camera
            for transfer in transfers {
                selectedTransfers.insert(transfer.id)
            }
        }
    }
}