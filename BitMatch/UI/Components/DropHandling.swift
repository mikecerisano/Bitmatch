// UI/Components/DropHandling.swift - Shared drop handling logic
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Handling Protocols

protocol DropHandlingView: View {
    var isDropTargeted: Bool { get set }
    var acceptedTypes: [UTType] { get }
    func onDrop(_ urls: [URL]) -> Bool
    func validateDrop(_ urls: [URL]) -> Bool
}

extension DropHandlingView {
    var acceptedTypes: [UTType] { [.fileURL] }
    
    func validateDrop(_ urls: [URL]) -> Bool {
        // Default validation - ensure all URLs are directories
        return urls.allSatisfy { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}

// MARK: - Common Drop Zone Styling

struct DropZoneStyle {
    let cornerRadius: CGFloat
    let strokeColor: Color
    let strokeWidth: CGFloat
    let backgroundColor: Color
    let overlayOpacity: Double
    
    static let `default` = DropZoneStyle(
        cornerRadius: 16,
        strokeColor: .green,
        strokeWidth: 2,
        backgroundColor: .white,
        overlayOpacity: 0.05
    )
    
    static let compact = DropZoneStyle(
        cornerRadius: 8,
        strokeColor: .blue,
        strokeWidth: 1.5,
        backgroundColor: .white,
        overlayOpacity: 0.03
    )
}

// MARK: - Drop Zone Modifier

struct DropZoneModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let style: DropZoneStyle
    let onDrop: ([URL]) -> Bool
    let validateDrop: ([URL]) -> Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isTargeted ? style.strokeColor : Color.clear,
                        lineWidth: style.strokeWidth
                    )
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
            )
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .fill(style.backgroundColor.opacity(style.overlayOpacity))
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        var urls: [URL] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        provider.loadObject(ofClass: NSURL.self) { nsurl, error in
            defer { semaphore.signal() }
            
            if let url = nsurl as? URL {
                urls.append(url)
            }
        }
        
        semaphore.wait()
        
        guard !urls.isEmpty, validateDrop(urls) else { return false }
        return onDrop(urls)
    }
}

// MARK: - View Extension

extension View {
    func dropZone(
        isTargeted: Binding<Bool>,
        style: DropZoneStyle = .default,
        validateDrop: @escaping ([URL]) -> Bool = { urls in
            return urls.allSatisfy { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        },
        onDrop: @escaping ([URL]) -> Bool
    ) -> some View {
        self.modifier(DropZoneModifier(
            isTargeted: isTargeted,
            style: style,
            onDrop: onDrop,
            validateDrop: validateDrop
        ))
    }
}

// MARK: - Directory Validation Helpers

struct DropValidation {
    static func directoriesOnly(_ urls: [URL]) -> Bool {
        return urls.allSatisfy { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
    
    static func imagesOnly(_ urls: [URL]) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
        return urls.allSatisfy { url in
            imageExtensions.contains(url.pathExtension.lowercased())
        }
    }
    
    static func singleItem(_ urls: [URL]) -> Bool {
        return urls.count == 1
    }
    
    static func multipleItems(_ urls: [URL]) -> Bool {
        return urls.count > 1
    }
    
    // Combine validators
    static func combine(_ validators: [(([URL]) -> Bool)]) -> ([URL]) -> Bool {
        return { urls in
            validators.allSatisfy { validator in
                validator(urls)
            }
        }
    }
}