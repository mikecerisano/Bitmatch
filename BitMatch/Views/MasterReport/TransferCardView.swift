// Views/MasterReport/TransferCardView.swift
import SwiftUI

struct TransferCardView: View {
    let transfer: TransferCard
    @Binding var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            Button {
                isSelected.toggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .green : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            // Camera icon
            Image(systemName: transfer.cameraIcon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 32)
            
            // Transfer info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transfer.cameraName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Verification badge
                    if transfer.verified {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                    }
                }
                
                Text("\(transfer.fileCount) files • \(ByteCountFormatter.string(fromByteCount: transfer.totalSize, countStyle: .file))")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                
                if transfer.rolls > 1 {
                    Text("\(transfer.rolls) rolls")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Text(transfer.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
                )
        )
        .onTapGesture {
            isSelected.toggle()
        }
    }
}