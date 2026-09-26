import Foundation

struct TransferMenuPresentation: Equatable {
    static let newTransferTitle = "New Transfer"
    static let unavailableEjectTitle = "Eject Card"
    static let ejectErrorTitle = "Could Not Eject Card"

    let newTransferEnabled: Bool
    let ejectTitle: String?

    static func make(
        isTransferRunning: Bool,
        outcome: TransferOutcomePresentation?,
        sourceName: String,
        sourceIsEjectable: Bool
    ) -> Self {
        let canEject = !isTransferRunning
            && sourceIsEjectable
            && outcome?.ejectIsPrimaryAction == true
        let card = sourceName.isEmpty ? "Card" : sourceName
        return Self(
            newTransferEnabled: !isTransferRunning,
            ejectTitle: canEject ? "Eject \(card)" : nil
        )
    }
}
