// Views/MasterReport/Components/MasterReportScanningView.swift
import SwiftUI

struct MasterReportScanningView: View {
    let isScanning: Bool
    
    var body: some View {
        HStack {
            Spacer()
            Card {
                VStack(spacing: 20) {
                    // Beautiful scanning animation
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.2), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(
                                AngularGradient(
                                    colors: [.green, .green.opacity(0.5), .clear],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(isScanning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)
                        
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                    }
                    
                    Text("Scanning for transfers...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("This may take a moment depending on drive size")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: 400)
            Spacer()
        }
    }
}