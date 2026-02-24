// Views/PreferencesWindow.swift - Dedicated preferences window
import SwiftUI
import AppKit

struct PreferencesWindow: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    // Tab selection
    @State private var selectedTab: PreferencesTab = .general
    
    enum PreferencesTab: String, CaseIterable {
        case general = "General"
        case reports = "Reports"
        case cameraDetection = "Camera Detection"
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .reports: return "doc.text"
            case .cameraDetection: return "externaldrive"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar
            
            Divider()
            
            // Content area
            Group {
                switch selectedTab {
                case .general:
                    generalPreferences
                case .reports:
                    reportPreferences
                case .cameraDetection:
                    cameraDetectionPreferences
                }
            }
            .frame(minWidth: 500, minHeight: 300)
            .padding(20)
        }
        .frame(width: 640, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Tab Bar
    
    @ViewBuilder
    private var tabBar: some View {
        HStack {
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))
                        Text(tab.rawValue)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .frame(width: 100, height: 50)
                }
                .buttonStyle(.plain)
                .background(
                    selectedTab == tab ?
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1)) :
                    nil
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - General Preferences
    
    @ViewBuilder
    private var generalPreferences: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                // Verification preferences
                GroupBox("Verification") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use checksum verification by default", isOn: $coordinator.settingsViewModel.prefs.verifyWithChecksum)
                            .toggleStyle(.checkbox)
                        
                        if coordinator.settingsViewModel.prefs.verifyWithChecksum {
                            HStack {
                                Text("Algorithm:")
                                Picker("", selection: $coordinator.settingsViewModel.prefs.checksumAlgorithm) {
                                    ForEach(ChecksumAlgorithm.allCases, id: \.self) { algorithm in
                                        Text(algorithm.rawValue).tag(algorithm)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Report Preferences

    @ViewBuilder
    private var reportPreferences: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Reports")
                .font(.title2)
                .fontWeight(.semibold)

            Toggle("Generate PDF & CSV reports automatically", isOn: $coordinator.settingsViewModel.prefs.makeReport)
                .toggleStyle(.checkbox)

            if coordinator.settingsViewModel.prefs.makeReport {
                GroupBox("Project Metadata") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Client Name", text: $coordinator.settingsViewModel.prefs.clientName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Project Name", text: $coordinator.settingsViewModel.prefs.projectName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Production Title", text: $coordinator.settingsViewModel.prefs.production)
                            .textFieldStyle(.roundedBorder)
                        TextField("Production Company", text: $coordinator.settingsViewModel.prefs.company)
                            .textFieldStyle(.roundedBorder)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $coordinator.settingsViewModel.prefs.notes)
                                .font(.system(size: 12))
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(8)
                }

                GroupBox("Output") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Generate PDF", isOn: $coordinator.settingsViewModel.prefs.generatePDF)
                            .toggleStyle(.checkbox)
                        Toggle("Generate CSV", isOn: $coordinator.settingsViewModel.prefs.generateCSV)
                            .toggleStyle(.checkbox)
                        Toggle("Include Thumbnails", isOn: $coordinator.settingsViewModel.prefs.includeThumbnails)
                            .toggleStyle(.checkbox)
                    }
                    .padding(8)
                }

                Button("Clear Report Metadata") {
                    clearReportMetadata()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut, value: coordinator.settingsViewModel.prefs.makeReport)
    }
    
    // MARK: - Camera Detection Preferences
    
    @ViewBuilder
    private var cameraDetectionPreferences: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Camera Detection")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Automatically detect and configure camera cards when they're connected to your Mac.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Main detection toggle
                Toggle("Enable automatic camera card detection", isOn: $coordinator.settingsViewModel.prefs.enableAutoCameraDetection)
                    .toggleStyle(.checkbox)
                    .onChange(of: coordinator.settingsViewModel.prefs.enableAutoCameraDetection) { oldValue, newValue in
                        coordinator.toggleCameraDetection(newValue)
                    }
                
                if coordinator.settingsViewModel.prefs.enableAutoCameraDetection {
                    VStack(alignment: .leading, spacing: 12) {
                        
                        Divider()
                        
                        Text("Detection Behavior")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        Toggle("Automatically set detected cameras as source", isOn: $coordinator.settingsViewModel.prefs.autoPopulateSource)
                            .toggleStyle(.checkbox)
                            .help("When enabled, detected camera cards will automatically be set as the source folder")
                        
                        Toggle("Show notifications when cameras are detected", isOn: $coordinator.settingsViewModel.prefs.showCameraDetectionNotifications)
                            .toggleStyle(.checkbox)
                            .help("Display system notifications when camera cards are detected")
                        
                        Divider()
                        
                        // Manual controls
                        HStack {
                            Button {
                                coordinator.rescanForCameras()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Rescan for Cameras")
                                }
                            }
                            .help("Manually scan for connected camera cards")
                            
                            Spacer()
                            
                            // Status indicator
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Supported cameras info
                        GroupBox("Supported Cameras") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BitMatch can automatically detect the following camera types:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()), 
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 4) {
                                    ForEach(["RED", "ARRI", "Blackmagic", "Sony", "Canon", "Panasonic", "GoPro", "DJI", "Fujifilm"], id: \.self) { camera in
                                        Text("• \(camera)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                    .padding(.leading, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut, value: coordinator.settingsViewModel.prefs.enableAutoCameraDetection)
    }
}

// MARK: - Preferences Window Controller

private extension PreferencesWindow {
    func clearReportMetadata() {
        var prefs = coordinator.settingsViewModel.prefs
        prefs.clientName = ""
        prefs.projectName = ""
        prefs.production = ""
        prefs.company = ""
        prefs.notes = ""
        coordinator.settingsViewModel.prefs = prefs
    }
}

class PreferencesWindowController: NSWindowController {
    convenience init(coordinator: AppCoordinator) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "BitMatch Preferences"
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
        window.contentView = NSHostingView(rootView: PreferencesWindow(coordinator: coordinator))
        
        self.init(window: window)
    }
}

#if DEBUG
struct PreferencesWindow_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesWindow(coordinator: AppCoordinator())
    }
}
#endif
