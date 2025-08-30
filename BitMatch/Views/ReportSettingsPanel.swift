// Views/ReportSettingsPanel.swift - Updated to use AppCoordinator
import SwiftUI

struct ReportSettingsPanel: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var isDraggingClientLogo = false
    @State private var isDraggingCompanyLogo = false
    @State private var logoRefreshTrigger = 0
    
    // Convenience accessor
    private var settings: SettingsViewModel { coordinator.settingsViewModel }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Report Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Divider()
                .overlay(Color.white.opacity(0.1))
            
            // Report fields
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Information")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                VStack(spacing: 12) {
                    CustomTextField(placeholder: "Client Name", text: $coordinator.settingsViewModel.prefs.client)
                    CustomTextField(placeholder: "Production Title", text: $coordinator.settingsViewModel.prefs.production)
                    CustomTextField(placeholder: "Production Company", text: $coordinator.settingsViewModel.prefs.company)
                }
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                // Logo section
                Text("Logos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 16) {
                    // Client Logo
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client Logo")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                        
                        LogoDropZone(
                            image: Binding(
                                get: { coordinator.settingsViewModel.prefs.clientLogoImage },
                                set: { 
                                    coordinator.settingsViewModel.prefs.clientLogoImage = $0
                                    // Force view refresh
                                    logoRefreshTrigger += 1
                                    coordinator.settingsViewModel.prefs.objectWillChange.send()
                                }
                            ),
                            isDragging: $isDraggingClientLogo,
                            placeholder: "Drop logo"
                        )
                        .id("clientLogo-\(logoRefreshTrigger)")
                    }
                    
                    // Company Logo
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Company Logo")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                        
                        LogoDropZone(
                            image: Binding(
                                get: { coordinator.settingsViewModel.prefs.companyLogoImage },
                                set: { 
                                    coordinator.settingsViewModel.prefs.companyLogoImage = $0
                                    // Force view refresh
                                    logoRefreshTrigger += 1
                                    coordinator.settingsViewModel.prefs.objectWillChange.send()
                                }
                            ),
                            isDragging: $isDraggingCompanyLogo,
                            placeholder: "Drop logo"
                        )
                        .id("companyLogo-\(logoRefreshTrigger)")
                    }
                }
                
                Spacer()
                
                // Info text
                Text("Reports will be saved as PDF and CSV with verification details and these project details.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.95))
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
        )
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.white.opacity(0.1)),
            alignment: .leading
        )
    }
}

// Custom themed text field
struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        TextField(placeholder, text: $text)
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
    }
}

