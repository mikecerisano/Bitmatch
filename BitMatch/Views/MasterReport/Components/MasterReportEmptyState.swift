// Views/MasterReport/Components/MasterReportEmptyState.swift
import SwiftUI

struct MasterReportEmptyState: View {
    let onScanDrive: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            Card {
                VStack(spacing: 24) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Generate Master Report")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Scan a drive to find all today's transfers and create a comprehensive production report")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    Button {
                        onScanDrive()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Scan Drive for Today's Transfers")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: 500)
            Spacer()
        }
    }
}