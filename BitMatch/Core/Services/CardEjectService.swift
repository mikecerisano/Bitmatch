// CardEjectService.swift - Ejects the source card from the finish screen.
#if os(macOS)
import Foundation
import AppKit

/// The finish screen's "Eject the card" action (Mac only: iPad and iPhone
/// have no removable-volume concept). `NSWorkspace` is not main-actor
/// isolated, so the eject call itself is safe to run off the main actor; it
/// can block briefly on slow media, so callers should not run it inline on a
/// UI-driving task they need to stay responsive.
enum CardEjectService {
    /// Whether `url` sits on a removable or ejectable volume, so the finish
    /// screen only offers to eject a card, never an internal folder.
    static func isEjectable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey]
        ) else {
            return false
        }
        return (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false)
    }

    /// Nil on success; a plain, displayable message on failure.
    static func eject(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
    }
}
#endif
