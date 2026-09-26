import AppKit
import Combine

/// Mac-only effects for transfer events. Safety remains visible in the UI;
/// sound and a Dock bounce only supplement it.
@MainActor
final class MacTransferSignalController {
    private let settings: GeneralSettings
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: SharedAppCoordinator) {
        settings = coordinator.generalSettings
        coordinator.transferSignals
            .receive(on: RunLoop.main)
            .sink { [weak self] signal in self?.handle(signal) }
            .store(in: &cancellables)
    }

    private func handle(_ signal: TransferSignal) {
        if settings.playSounds {
            let name: NSSound.Name
            let volume: Float
            switch signal {
            case .safeToErase:
                name = NSSound.Name("Glass")
                volume = 0.25
            case .attention:
                name = NSSound.Name("Basso")
                volume = 0.4
            }
            if let sound = NSSound(named: name) {
                sound.volume = volume
                sound.play()
            }
        }
        if signal == .attention, NSApp?.isActive == false {
            NSApp?.requestUserAttention(.criticalRequest)
        }
    }
}
