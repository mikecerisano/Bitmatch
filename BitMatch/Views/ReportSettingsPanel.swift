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
            headerSection
            Divider().overlay(Color.white.opacity(0.1))
            contentSection
        }
        .padding(24)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(backgroundView)
        .overlay(borderOverlay, alignment: .leading)
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Text("Report Settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
    }
    
    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            projectInformationSection
            Divider().overlay(Color.white.opacity(0.1))
            logoSection
            Spacer()
            infoText
            clearReportInfoButton
        }
    }
    
    @ViewBuilder
    private var projectInformationSection: some View {
        Text("Project Information")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
        
        VStack(spacing: 12) {
            CustomTextField(placeholder: "Client Name", text: $coordinator.settingsViewModel.prefs.clientName)
            CustomTextField(placeholder: "Production Title", text: $coordinator.settingsViewModel.prefs.production)
            CustomTextField(placeholder: "Production Company", text: $coordinator.settingsViewModel.prefs.company)
        }
    }
    
    @ViewBuilder
    private var logoSection: some View {
        Text("Logos")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
        
        HStack(spacing: 16) {
            clientLogoView
            companyLogoView
        }
    }
    
    @ViewBuilder
    private var clientLogoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Client Logo")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            
            LogoDropZone(
                image: clientLogoBinding,
                isDragging: $isDraggingClientLogo,
                placeholder: "Drop logo"
            )
            .id("clientLogo-\(logoRefreshTrigger)")
        }
    }
    
    @ViewBuilder
    private var companyLogoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Company Logo")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            
            LogoDropZone(
                image: companyLogoBinding,
                isDragging: $isDraggingCompanyLogo,
                placeholder: "Drop logo"
            )
            .id("companyLogo-\(logoRefreshTrigger)")
        }
    }
    
    @ViewBuilder
    private var infoText: some View {
        Text("Reports will be saved as PDF and CSV with verification details and these project details.")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var clearReportInfoButton: some View {
        Button {
            clearReportInfo()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Clear Report Info")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.red.opacity(0.25), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        Rectangle()
            .fill(Color.black.opacity(0.95))
            .overlay(backgroundGradient)
    }
    
    @ViewBuilder
    private var backgroundGradient: some View {
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
    }
    
    @ViewBuilder
    private var borderOverlay: some View {
        Rectangle()
            .frame(width: 1)
            .foregroundColor(.white.opacity(0.1))
    }
    
    // MARK: - Binding Helpers
    
    private var clientLogoBinding: Binding<NSImage?> {
        Binding(
            get: { nil }, // SharedModels.ReportPrefs doesn't have clientLogoImage
            set: { _ in
                // SharedModels.ReportPrefs doesn't have clientLogoImage - ignore
                logoRefreshTrigger += 1
                // ReportPrefs doesn't have objectWillChange - use settingsViewModel instead
                coordinator.settingsViewModel.objectWillChange.send()
            }
        )
    }
    
    private var companyLogoBinding: Binding<NSImage?> {
        Binding(
            get: { nil }, // SharedModels.ReportPrefs doesn't have companyLogoImage
            set: { _ in
                // SharedModels.ReportPrefs doesn't have companyLogoImage - ignore
                logoRefreshTrigger += 1
                // ReportPrefs doesn't have objectWillChange - use settingsViewModel instead
                coordinator.settingsViewModel.objectWillChange.send()
            }
        )
    }
}

// MARK: - Actions
private extension ReportSettingsPanel {
    func clearReportInfo() {
        var prefs = coordinator.settingsViewModel.prefs
        prefs.clientName = ""
        prefs.projectName = ""
        prefs.production = ""
        prefs.company = ""
        prefs.notes = ""
        // Persist via SettingsViewModel published property update
        coordinator.settingsViewModel.prefs = prefs
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
