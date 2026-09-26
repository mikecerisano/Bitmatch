import SwiftUI
import BitMatchEngine

struct TransferRecordRow<Trailing: View>: View {
    let record: LocalTransferRecord
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let state = TransferLibraryPresentation.stateLabel(record.state, verificationMode: record.verificationMode)
        let detail = TransferLibraryPresentation.detailLine(destinationCount: record.destinations.count, fileCount: record.results.count)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                (Text(record.createdAt, style: .date) + Text(" · \(detail)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            statePill(state)
            trailing()
        }
        .padding(.vertical, 4)
    }

    private func statePill(_ state: TransferLibraryPresentation.StateLabel) -> some View {
        Text(state.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(state.tone.color.opacity(0.15), in: Capsule())
            .accessibilityLabel(state.title)
    }
}
