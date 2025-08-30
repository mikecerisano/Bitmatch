#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// NSView-based image drop zone for reliable image drag and drop
struct ImageDropZoneView: NSViewRepresentable {
    let onDrop: (NSImage) -> Void
    @Binding var isTargeted: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = ImageDropView()
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

class ImageDropView: NSView {
    var onDrop: ((NSImage) -> Void)?
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
        // Register for image drag and drop
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("public.image"),
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            .tiff
        ])
        
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        
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
        
        // Try different ways to get the image
        
        // Method 1: Direct image data
        if let imageData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: imageData) {
            onDrop?(image)
            return true
        }
        
        if let imageData = pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            onDrop?(image)
            return true
        }
        
        if let imageData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")),
           let image = NSImage(data: imageData) {
            onDrop?(image)
            return true
        }
        
        // Method 2: File URL to image
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            
            // Check if it's an image file
            let imageExtensions = ["png", "jpg", "jpeg", "tiff", "gif", "bmp", "ico", "webp"]
            let fileExtension = url.pathExtension.lowercased()
            
            if imageExtensions.contains(fileExtension) {
                if let image = NSImage(contentsOf: url) {
                    onDrop?(image)
                    return true
                }
            }
        }
        
        // Method 3: Generic image type
        if let imageData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.image")),
           let image = NSImage(data: imageData) {
            onDrop?(image)
            return true
        }
        
        return false
    }
    
    private func canHandleDrag(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        // Check for direct image data
        if pasteboard.data(forType: .tiff) != nil ||
           pasteboard.data(forType: .png) != nil ||
           pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) != nil ||
           pasteboard.data(forType: NSPasteboard.PasteboardType("public.image")) != nil {
            return true
        }
        
        // Check for image files
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            let imageExtensions = ["png", "jpg", "jpeg", "tiff", "gif", "bmp", "ico", "webp"]
            let fileExtension = url.pathExtension.lowercased()
            return imageExtensions.contains(fileExtension)
        }
        
        return false
    }
}
#endif