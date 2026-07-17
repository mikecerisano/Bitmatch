import AppKit

enum InterfaceLabLaunchConfiguration {
    static let arguments = ["--interface-lab"]

    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(Self.arguments[0])
    }
}

@MainActor
enum InterfaceLabLauncher {
    static func open() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = InterfaceLabLaunchConfiguration.arguments
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                AppLogger.error("Could not open interface lab: \(error.localizedDescription)", category: .general)
            }
        }
    }
}
