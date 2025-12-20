#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// NSView-based drop zone that should work more reliably than SwiftUI's onDrop
struct DropZoneView: NSViewRepresentable {
    let onDrop: ([URL]) -> Void  // Changed to accept multiple URLs
    @Binding var isTargeted: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = DropView()
        view.onDrop = onDrop
        view.onTargetChanged = { isTargeted in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms delay
                self.isTargeted = isTargeted
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed
    }
}

class DropView: NSView {
    var onDrop: (([URL]) -> Void)?  // Changed to accept multiple URLs
    var onTargetChanged: ((Bool) -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Register for drag and drop
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.folder")
        ])
        
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        SharedLogger.debug("Available types: \(sender.draggingPasteboard.types ?? [])", category: .transfer)

        // Check if we can handle this drag
        if canHandleDrag(sender) {
            onTargetChanged?(true)
            return .copy
        }
        
        return []
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return canHandleDrag(sender) ? .copy : []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        
        let pasteboard = sender.draggingPasteboard
        var droppedURLs: [URL] = []
        
        // Try to get multiple URLs from readObjects (this handles multi-selection)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for (index, url) in urls.enumerated() {
                SharedLogger.debug("  URL \(index + 1): \(url.path)", category: .transfer)
            }
            droppedURLs = urls
        } else if let fileURL = pasteboard.string(forType: .fileURL),
                  let url = URL(string: fileURL) {
            droppedURLs = [url]
        }
        
        guard !droppedURLs.isEmpty else {
            SharedLogger.warning("Could not extract any URLs from drag", category: .transfer)
            return false
        }
        
        return handleDroppedURLs(droppedURLs)
    }
    
    private func canHandleDrag(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ||
               pasteboard.types?.contains(.fileURL) == true
    }
    
    private func handleDroppedURLs(_ urls: [URL]) -> Bool {
        
        var validDirectories: [URL] = []
        
        // Check each URL to ensure it's a directory
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                validDirectories.append(url)
            } else {
                SharedLogger.warning("Skipping non-directory: \(url.lastPathComponent)", category: .transfer)
            }
        }
        
        guard !validDirectories.isEmpty else {
            SharedLogger.warning("No valid directories found in drop", category: .transfer)
            return false
        }
        
        onDrop?(validDirectories)
        return true
    }
}
#endif