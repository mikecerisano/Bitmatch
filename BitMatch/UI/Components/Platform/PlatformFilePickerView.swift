// UI/Components/Platform/PlatformFilePickerView.swift
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Cross-platform file picker that adapts to macOS drag-drop or iOS document picker
struct PlatformFilePickerView: View {
    let title: String
    let subtitle: String?
    let onFileSelected: ([URL]) -> Void
    let allowsMultipleSelection: Bool
    let isTargeted: Binding<Bool>?
    
    @State private var isShowingPicker = false
    
    // MARK: - Platform Manager Access
    
    private var currentPlatformManager: any PlatformManager {
        #if os(macOS)
        return MacOSPlatformManager.shared
        #else
        return IOSPlatformManager.shared
        #endif
    }
    
    init(
        title: String,
        subtitle: String? = nil,
        allowsMultipleSelection: Bool = false,
        isTargeted: Binding<Bool>? = nil,
        onFileSelected: @escaping ([URL]) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.allowsMultipleSelection = allowsMultipleSelection
        self.isTargeted = isTargeted
        self.onFileSelected = onFileSelected
    }
    
    var body: some View {
        if currentPlatformManager.supportsDragAndDrop {
            // macOS: Use drag-and-drop interface
            macOSDragDropView
        } else {
            // iOS: Use tap-to-select interface
            iOSTapToSelectView
        }
    }
    
    @ViewBuilder
    private var macOSDragDropView: some View {
        #if os(macOS)
        // Use existing DropZoneView
        ZStack {
            cardContent
            
            DropZoneView(
                onDrop: onFileSelected,
                isTargeted: isTargeted ?? .constant(false)
            )
        }
        #endif
    }
    
    @ViewBuilder
    private var iOSTapToSelectView: some View {
        Button {
            Task {
                await selectFiles()
            }
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                // Show platform-specific hint
                Text(platformHint)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var platformHint: String {
        if currentPlatformManager.supportsDragAndDrop {
            return "Drag folders here or click to select"
        } else {
            return "Tap to select from Files app"
        }
    }
    
    private func selectFiles() async {
        if allowsMultipleSelection {
            let urls = await currentPlatformManager.fileSystem.selectDestinationFolders()
            if !urls.isEmpty {
                onFileSelected(urls)
            }
        } else {
            if let url = await currentPlatformManager.fileSystem.selectSourceFolder() {
                onFileSelected([url])
            }
        }
    }
}