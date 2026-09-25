// IOSDriverScanner.swift - iOS folder picker for the Master Report
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Presents the Files document picker so the Master Report can read a backup
/// drive, card reader or folder. iOS lets an app read removable media only
/// through a location the person picks here; `ReportScanner` starts the
/// security-scoped access the picked URL carries. The scan rules themselves
/// are shared with the Mac in `ReportScanner`.
@MainActor
class IOSDriverScanner: NSObject {
    private static var currentDrivePickerDelegate: DrivePickerDelegate?

    /// Returns the picked folder, or nil when the person cancelled or the
    /// picker could not be shown.
    static func chooseFolder() async -> URL? {
        await withCheckedContinuation { continuation in
            let picker = makeDrivePicker { url in
                continuation.resume(returning: url)
            }
            guard let presenter = topViewController() else {
                currentDrivePickerDelegate = nil
                continuation.resume(returning: nil)
                return
            }
            if UIDevice.current.userInterfaceIdiom == .pad {
                picker.modalPresentationStyle = .formSheet
            }
            presenter.present(picker, animated: true)
        }
    }

    /// The view controller to present from: the key window's root, or
    /// whatever it is already presenting (a sheet, say).
    static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard var current = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else {
            return nil
        }
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    private static func makeDrivePicker(completion: @escaping (URL?) -> Void) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        let delegate = DrivePickerDelegate { url in
            currentDrivePickerDelegate = nil
            completion(url)
        }
        currentDrivePickerDelegate = delegate
        picker.delegate = delegate
        return picker
    }

    #if DEBUG
    static var hasRetainedDrivePickerDelegateForTesting: Bool {
        currentDrivePickerDelegate != nil
    }

    static func clearRetainedDrivePickerDelegateForTesting() {
        currentDrivePickerDelegate = nil
    }

    static func makeDrivePickerForTesting(completion: @escaping (URL?) -> Void) -> UIDocumentPickerViewController {
        makeDrivePicker(completion: completion)
    }
    #endif
}

// MARK: - Document Picker Delegate for Drive Selection

private class DrivePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
