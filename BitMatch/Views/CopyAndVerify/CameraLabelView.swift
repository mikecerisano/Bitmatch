import SwiftUI

// MARK: - Camera Label Configuration View
struct CameraLabelView: View {
    @Binding var settings: CameraLabelSettings
    var detectedCamera: CameraType = .generic
    var fingerprint: CameraMemoryService.CameraFingerprint? = nil
    var sourceURL: URL? = nil  // Added parameter for source folder
    
    private var previewBase: String {
        guard let sourceURL = sourceURL else {
            return "" // No base if no source selected
        }
        return sourceURL.lastPathComponent
    }
    
    private var presets: [String] {
        var basicPresets = ["A-Cam", "Main", "B-Cam", "C-Cam", "D-Cam", "Audio", "Drone"]
        
        // Add camera model as an option if detected
        if detectedCamera != .generic {
            let cameraLabel = getCameraLabel(for: detectedCamera)
            if !cameraLabel.isEmpty && !basicPresets.contains(cameraLabel) {
                basicPresets.insert(cameraLabel, at: 0)
            }
        }
        
        return basicPresets
    }
    
    private func getCameraLabel(for camera: CameraType) -> String {
        switch camera {
        case .arriAlexa: return "ALEXA"
        case .arriAmira: return "AMIRA"
        case .redDragon: return "RED"
        case .sonyFX6: return "FX6"
        case .sonyFX3: return "FX3"
        case .sonyA7S: return "A7S"
        case .canonC70: return "C70"
        case .blackmagicPocket: return "BMPCC"
        case .dji: return "DRONE"
        case .gopro: return "GOPRO"
        case .generic: return ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            Text("Camera Labeling")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            // Show fingerprint info if available
            if let fingerprint = fingerprint {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.5))
                    Text("Detected: \(fingerprint.displayName)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
            }
            
            // Quick Presets and Custom Camera Label - side by side
            HStack(alignment: .top, spacing: 20) {
                // Quick Presets on the left
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    VStack(spacing: 6) { // Increased vertical spacing for iPad
                        HStack(spacing: 6) { // Increased horizontal spacing for iPad
                            ForEach(presets.prefix(4), id: \.self) { preset in
                                presetButton(for: preset)
                            }
                        }
                        
                        if presets.count > 4 {
                            HStack(spacing: 6) { // Increased horizontal spacing for iPad
                                ForEach(presets.dropFirst(4), id: \.self) { preset in
                                    presetButton(for: preset)
                                }
                            }
                        }
                    }
                }
                
                // Custom Camera Label on the right
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Camera Label")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    TextField("Enter label (e.g., A-Cam)", text: $settings.label)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                        .frame(width: 180) // Fixed width for consistency
                }
                
                Spacer() // Push everything to the left
            }
            
            // Position Toggle and Separator in one row to save space
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label Position")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Picker("", selection: $settings.position) {
                        ForEach(CameraLabelSettings.LabelPosition.allCases, id: \.self) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .frame(maxWidth: 180) // Constrain width for compact buttons
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Separator")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    HStack(spacing: 4) {
                        ForEach(CameraLabelSettings.Separator.allCases, id: \.self) { sep in
                            Button {
                                settings.separator = sep
                            } label: {
                                Text(sep.displayName)
                                    .font(.system(size: 11))
                                    .foregroundColor(settings.separator == sep ?
                                        .black : .white.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(settings.separator == sep ?
                                                Color.green :
                                                Color.white.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Live Preview - adaptive width
            if !settings.label.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    HStack {
                        Text(previewText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.green.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Spacer()
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .opacity)
                ))
            }
            
            // Auto-numbering toggle
            Toggle("Auto-number if folder exists", isOn: $settings.autoNumber)
                .toggleStyle(.switch)
                .tint(.green)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
            
            // Camera grouping toggle
            Toggle("Group files by camera type in subfolders", isOn: $settings.groupByCamera)
                .toggleStyle(.switch)
                .tint(.blue)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)  // Reduced horizontal padding to eliminate red box space
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settings.label)
    }
    
    private var previewText: String {
        if previewBase.isEmpty {
            // No source selected, just show the label with underscore
            return settings.label.isEmpty ? "Label_" : "\(settings.label)_"
        } else {
            // Source selected, show full formatted name
            return settings.formatFolderName(previewBase)
        }
    }
    
    @ViewBuilder
    private func presetButton(for preset: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) {
                settings.label = preset
            }
        } label: {
            Text(preset)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(settings.label == preset ? .black : .white.opacity(0.7))
                .padding(.horizontal, 8)  // Increased from 6 for better iPad touch targets
                .padding(.vertical, 6)   // Increased from 4 for better iPad touch targets
                .background(
                    RoundedRectangle(cornerRadius: 6)  // Slightly larger corner radius
                        .fill(settings.label == preset ?
                            Color.green :
                            Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}
