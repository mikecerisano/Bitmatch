#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LogoDropZone: View {
    @Binding var image: NSImage?
    @Binding var isDragging: Bool
    let placeholder: String
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                       style: StrokeStyle(lineWidth: isDragging ? 2 : 1,
                                         dash: isDragging ? [] : [5, 3]))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .frame(width: 100, height: 60)
            
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 90, height: 50)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.image = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -8)
                    }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(placeholder)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            
            // Overlay the NSView-based image drop zone when no image is set
            if image == nil {
                ImageDropZoneView(onDrop: { droppedImage in
                    self.image = droppedImage
                }, isTargeted: $isDragging)
                .frame(width: 100, height: 60)  // Match the outer frame exactly
                .allowsHitTesting(true)
            }
        }
        .onTapGesture {
            selectImageFile()
        }
    }
    
    private func selectImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                self.image = image
            }
        }
    }
}
#endif
