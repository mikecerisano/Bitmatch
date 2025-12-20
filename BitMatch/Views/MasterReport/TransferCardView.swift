// Views/MasterReport/TransferCardView.swift
import SwiftUI

struct TransferCardView: View {
    let transfer: TransferCard
    @Binding var isSelected: Bool
    
    var body: some View {
        cardContent
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(cardBackground)
            .onTapGesture {
                isSelected.toggle()
            }
    }
    
    @ViewBuilder
    private var cardContent: some View {
        HStack(spacing: 16) {
            selectionButton
            cameraIconView
            transferInfoSection
            Spacer()
        }
    }
    
    @ViewBuilder
    private var selectionButton: some View {
        Button {
            isSelected.toggle()
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isSelected ? .green : .white.opacity(0.4))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var cameraIconView: some View {
        Image(systemName: cameraIcon(for: transfer))
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(.blue)
            .frame(width: 32)
    }
    
    @ViewBuilder
    private var transferInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            fileSizeText
            rollsText
            timestampText
        }
    }
    
    @ViewBuilder
    private var headerRow: some View {
        HStack {
            Text(transfer.cameraName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            verificationBadge
        }
    }
    
    @ViewBuilder
    private var verificationBadge: some View {
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
    
    @ViewBuilder
    private var fileSizeText: some View {
        Text("\(transfer.fileCount) files • \(ByteCountFormatter.string(fromByteCount: transfer.totalSize, countStyle: .file))")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.7))
    }
    
    @ViewBuilder
    private var rollsText: some View {
        // Note: rolls property doesn't exist in TransferCard model, commenting out for now
        // if transfer.rolls > 1 {
        //     Text("\(transfer.rolls) rolls")
        //         .font(.system(size: 11))
        //         .foregroundColor(.white.opacity(0.5))
        // }
        EmptyView()
    }
    
    @ViewBuilder
    private var timestampText: some View {
        Text(transfer.timestamp, style: .time)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.5))
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1)
            )
    }
    
    // MARK: - Helper Methods
    private func cameraIcon(for transfer: TransferCard) -> String {
        // Use camera card type if available, otherwise default icon
        if let cameraCard = transfer.cameraCard {
            return systemImage(for: cameraCard.cameraType)
        }
        return "camera.fill"
    }
    
    private func systemImage(for cameraType: CameraType) -> String {
        switch cameraType {
        case .sony, .sonyFX6, .sonyFX3, .sonyA7S:
            return "camera.fill"
        case .canon, .canonC70:
            return "camera.fill"
        case .arri, .arriAlexa, .arriAmira:
            return "camera.aperture"
        case .red, .redCamera, .redDragon:
            return "camera.circle"
        case .blackmagic, .blackmagicPocket:
            return "camera.macro"
        case .panasonic:
            return "camera.fill"
        case .fujifilm:
            return "camera.metering.spot"
        case .nikon:
            return "camera.fill"
        case .gopro:
            return "camera.on.rectangle"
        case .dji:
            return "camera.on.rectangle.fill"
        case .insta360:
            return "camera.rotate"
        case .genericDCIM, .genericMedia, .generic:
            return "camera"
        }
    }
}
