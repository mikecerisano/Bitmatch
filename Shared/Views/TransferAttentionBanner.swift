import SwiftUI

/// The "review in Transfers" banner shown above the main screen on Mac, iPad
/// and iPhone. Shows nothing when no transfer needs review.
struct TransferAttentionBanner: View {
    let needsAttentionCount: Int
    let openTransfers: () -> Void

    var body: some View {
        if let title = TransferLibraryPresentation.bannerTitle(needsAttentionCount: needsAttentionCount) {
            Button(action: openTransfers) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    #if os(iOS)
                    .frame(minHeight: 44)
                    #endif
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.orange)
            .accessibilityHint("Opens Transfers")
        }
    }
}
