struct TransferOperationPresentation: Equatable {
    let title: String
    let symbol: String
    let controlTitle: String
    let controlSymbol: String

    static func make(state: OperationState, isPaused: Bool) -> TransferOperationPresentation {
        if isPaused {
            return TransferOperationPresentation(
                title: "Transfer paused",
                symbol: "pause.circle.fill",
                controlTitle: "Resume",
                controlSymbol: "play.fill"
            )
        }

        switch state {
        case .copying:
            return TransferOperationPresentation(
                title: "Copying",
                symbol: "arrow.right.circle.fill",
                controlTitle: "Pause",
                controlSymbol: "pause.fill"
            )
        case .verifying:
            return TransferOperationPresentation(
                title: "Verifying",
                symbol: "checkmark.shield.fill",
                controlTitle: "Pause",
                controlSymbol: "pause.fill"
            )
        case .resuming:
            return TransferOperationPresentation(
                title: "Resuming",
                symbol: "arrow.clockwise.circle.fill",
                controlTitle: "Pause",
                controlSymbol: "pause.fill"
            )
        default:
            return TransferOperationPresentation(
                title: "Preparing",
                symbol: "circle.dotted",
                controlTitle: "Pause",
                controlSymbol: "pause.fill"
            )
        }
    }
}
