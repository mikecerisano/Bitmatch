// CopyAndVerifyView.swift - Main copy and verify interface for iPad
import SwiftUI

struct CopyAndVerifyView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var cameraLabelExpanded = false
    @State private var verificationModeExpanded = false
    @State private var optionsExpanded = false
    @State private var usesProjectWorkflow = false

    private var hasPreparedProjectTransfer: Bool {
        coordinator.photographerJobViewModel.hasPreparedIngestAwaitingStart
    }

    private var plan: TransferPlanPresentation {
        let readiness = coordinator.operationReadinessAssessment
        var blockingIssues = readiness.issues
        if coordinator.sourceURL == nil || coordinator.destinationURLs.isEmpty {
            // TransferPlanPresentation renders missing locations as setup states.
            // Preserve only actual validation findings as blocked states.
            blockingIssues.removeAll {
                $0 == "No source folder selected" || $0 == "No destination folders selected"
            }
        }
        return TransferPlanPresentation.make(
            sourceURL: coordinator.sourceURL,
            sourceInfo: coordinator.sourceFolderInfo?.asFolderInfo,
            destinationURLs: coordinator.destinationURLs,
            verificationMode: coordinator.verificationMode,
            cameraSettings: coordinator.cameraLabelSettings,
            reportSettings: coordinator.reportSettings,
            isAnalyzing: coordinator.sourceURL.map { coordinator.isFolderInfoLoading(for: $0) } ?? false,
            blockingIssues: blockingIssues,
            warnings: readiness.warnings
        )
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Enhanced header with professional branding
            CopyAndVerifyHeaderView()
            
            // Full interface
            VStack(spacing: 20) {
                // The selection cards remain the owner of iPad Files picker actions.
                EnhancedSourceDestinationView(coordinator: coordinator)

                MobileTransferWorkflowPicker(
                    usesProjectWorkflow: $usesProjectWorkflow,
                    isProjectPrepared: hasPreparedProjectTransfer
                )

                if usesProjectWorkflow || hasPreparedProjectTransfer {
                    MobileProjectSetupCard(coordinator: coordinator)
                }

                IpadTransferPlanPreflightCard(plan: plan)
                IpadTransferPlanOptionSummary(plan: plan, isQuickMode: coordinator.verificationMode == .quick)

                DisclosureGroup(isExpanded: $optionsExpanded) {
                    VStack(spacing: 14) {
                        CollapsibleLabelingSection(
                            coordinator: coordinator,
                            isExpanded: $cameraLabelExpanded
                        )
                        CollapsibleVerificationSection(
                            coordinator: coordinator,
                            isExpanded: $verificationModeExpanded
                        )
                        ReportToggleCard(coordinator: coordinator)
                    }
                    .padding(.top, 12)
                } label: {
                    HStack {
                        Label("Options", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(coordinator.verificationMode.rawValue) · \(coordinator.reportSettings.makeReport ? "Reports on" : "Reports off")")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.035))
                )
                .accessibilityLabel("Options")
                .accessibilityHint("Shows camera labels, verification, and report settings")

                StartTransferButtonView(
                    coordinator: coordinator,
                    plan: plan,
                    showsReadinessBanner: false,
                    startsProjectTransfer: usesProjectWorkflow || hasPreparedProjectTransfer
                )
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: cameraLabelExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: verificationModeExpanded)
    }
}

private struct MobileTransferWorkflowPicker: View {
    @Binding var usesProjectWorkflow: Bool
    let isProjectPrepared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(spacing: 8) { buttons }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transfer workflow")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: usesProjectWorkflow)
    }

    @ViewBuilder private var buttons: some View {
        workflowButton(.quick, selected: !usesProjectWorkflow && !isProjectPrepared) {
            usesProjectWorkflow = false
        }
        .disabled(isProjectPrepared)
        workflowButton(.project, selected: usesProjectWorkflow || isProjectPrepared) {
            usesProjectWorkflow = true
        }
    }

    private func workflowButton(
        _ workflow: TransferWorkflowPresentation,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2), action)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: workflow.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selected ? .green : .white.opacity(0.55))
                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.title).font(.system(size: 12, weight: .semibold))
                    Text(workflow.detail).font(.system(size: 10)).foregroundColor(.white.opacity(0.58))
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
            }
            .foregroundColor(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.green.opacity(0.09) : Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.green.opacity(0.25) : Color.white.opacity(0.08)))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workflow.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

private struct MobileProjectSetupCard: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @State private var clientName = ""
    @State private var jobName = ""
    @State private var eventDate = Date()
    @State private var contributorName = ""
    @State private var cameraName = ""
    @State private var isExpanded = true
    @State private var showLayers = false
    @State private var remoteExpanded = false
    @State private var didHydrate = false

    private var viewModel: PhotographerJobViewModel { coordinator.photographerJobViewModel }
    private var cardNumber: Int { viewModel.proposedCardNumber(cameraName: cameraName) }
    private var setupSignature: PhotographerSetupSignature {
        PhotographerSetupSignature(
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines),
            jobName: jobName.trimmingCharacters(in: .whitespacesAndNewlines),
            eventDate: eventDate,
            photographerName: contributorName.trimmingCharacters(in: .whitespacesAndNewlines),
            cameraName: cameraName.trimmingCharacters(in: .whitespacesAndNewlines),
            cardNumber: cardNumber,
            recipe: viewModel.draftRecipe
        )
    }
    private var presentation: PhotographerJobSetupPresentation {
        PhotographerJobSetupPresentation.make(
            clientName: clientName,
            jobName: jobName,
            eventDate: eventDate,
            photographerName: contributorName,
            cameraName: cameraName,
            cardNumber: cardNumber,
            recipe: viewModel.draftRecipe,
            workflow: viewModel.selectedWorkflow,
            duplicateWarningText: viewModel.duplicateWarning?.message,
            hasSource: coordinator.sourceURL != nil,
            isPreparing: viewModel.isPreparing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.green)
                    Image(systemName: "camera.fill").foregroundColor(.white.opacity(0.68))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project setup").font(.system(size: 15, weight: .semibold))
                        if !isExpanded { Text(presentation.collapsedSummary).font(.system(size: 11)).foregroundColor(.white.opacity(0.58)).lineLimit(1) }
                    }
                    Spacer()
                    Text(presentation.presetTitle.uppercased())
                        .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundColor(.green)
                }
                .foregroundColor(.white).contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Picker("Workflow", selection: Binding(get: { viewModel.selectedWorkflow }, set: { viewModel.selectWorkflow($0) })) {
                    ForEach(ProjectWorkflow.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isPreparing || viewModel.isWorkflowLocked)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { identityFields }
                    VStack(spacing: 10) { identityFields }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { mediaFields }
                    VStack(spacing: 10) { mediaFields }
                }

                DisclosureGroup("Folder layers", isExpanded: $showLayers) {
                    VStack(spacing: 8) {
                        ForEach(viewModel.draftRecipe.layers) { layer in
                            Toggle(layerTitle(layer.kind), isOn: Binding(
                                get: { viewModel.draftRecipe.layers.first(where: { $0.id == layer.id })?.isEnabled ?? false },
                                set: { viewModel.setDraftLayer(layer.id, isEnabled: $0) }
                            ))
                            .tint(.green)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

                packageRoute
                remoteDestination
                feedback
                setupAction
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.035)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08))))
        .onAppear(perform: hydrateOnce)
        .onChange(of: setupSignature) { _, signature in viewModel.updateSetupSignature(signature) }
        .onChange(of: viewModel.isPreparing) { wasPreparing, preparing in
            if wasPreparing, !preparing, viewModel.activeCardDraft != nil { isExpanded = false }
        }
    }

    @ViewBuilder private var identityFields: some View {
        setupField("Client", text: $clientName, prompt: "Smith")
        setupField("Job name", text: $jobName, prompt: "Smith Wedding")
        DatePicker("Date", selection: $eventDate, displayedComponents: .date)
            .labelsHidden().datePickerStyle(.compact).frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var mediaFields: some View {
        setupField(viewModel.selectedWorkflow.contributorLabel, text: $contributorName, prompt: "Mike")
        setupField("Camera", text: $cameraName, prompt: "Sony A7 IV")
        VStack(alignment: .leading, spacing: 5) {
            Text(viewModel.selectedWorkflow.sourceUnitLabel.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundColor(.white.opacity(0.48))
            Text(String(format: "%03d", cardNumber)).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
    }

    private var packageRoute: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PACKAGE ROUTE").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundColor(.white.opacity(0.48))
            Text(presentation.pathPreview).font(.system(size: 12, design: .monospaced)).foregroundColor(.white.opacity(0.78)).lineLimit(2)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.16)))
    }

    private var remoteDestination: some View {
        DisclosureGroup("Off-site backup", isExpanded: $remoteExpanded) {
            if viewModel.remoteProfiles.isEmpty {
                Text("Save a destination in BitMatch on Mac, then choose it here. This device preserves the project route; SSH uploads continue on Mac.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.58)).padding(.top, 6)
            } else {
                Picker("Destination", selection: Binding(
                    get: { viewModel.activeJob?.remoteBackupConfiguration?.destinationProfileID },
                    set: { viewModel.selectRemoteProfile($0) }
                )) {
                    Text("Not selected").tag(UUID?.none)
                    ForEach(viewModel.remoteProfiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                }
                .pickerStyle(.menu).padding(.top, 6)
            }
        }
        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.82))
    }

    @ViewBuilder private var feedback: some View {
        if let error = viewModel.preparationError ?? viewModel.lastError {
            Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundColor(.orange)
        } else if !presentation.blockers.isEmpty {
            Text(presentation.blockers.joined(separator: ". ") + ".").font(.system(size: 12)).foregroundColor(.white.opacity(0.56))
        }
    }

    private var setupAction: some View {
        HStack {
            if viewModel.isPreparing {
                ProgressView().controlSize(.small)
                Text("Preparing (viewModel.selectedWorkflow.sourceUnitLabel.lowercased())…").font(.system(size: 12)).foregroundColor(.white.opacity(0.68))
                Button("Cancel") { viewModel.cancelPreparingDraftCard() }.buttonStyle(.bordered).controlSize(.small)
            }
            Spacer()
            if let state = viewModel.activeCard?.localState, state != .notStarted && state != .copying && state != .verifying {
                Button("Set up next (viewModel.selectedWorkflow.sourceUnitLabel.lowercased())") { viewModel.resetForNextCard(); isExpanded = true }.buttonStyle(.bordered)
            } else {
                Button("Set up (viewModel.selectedWorkflow.sourceUnitLabel.lowercased())") {
                    guard let sourceURL = coordinator.sourceURL else { return }
                    viewModel.startPreparingDraftCard(sourceURL: sourceURL, setupSignature: setupSignature)
                }
                .buttonStyle(.borderedProminent).tint(.green).disabled(!presentation.canSetUpCard)
            }
        }
    }

    private func setupField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundColor(.white.opacity(0.48))
            TextField(prompt, text: text).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
        }
    }
    private func layerTitle(_ kind: FolderLayerKind) -> String {
        switch kind {
        case .photographer: viewModel.selectedWorkflow.contributorLabel
        case .cardNumber: "(viewModel.selectedWorkflow.sourceUnitLabel) number"
        case .dateAndJob: "Date and job"
        case .originals: "Originals"
        case .camera: "Camera"
        }
    }
    private func hydrateOnce() {
        guard !didHydrate else { return }; didHydrate = true
        if let job = viewModel.activeJob { clientName = job.clientName; jobName = job.jobName; eventDate = job.eventDate; viewModel.draftRecipe = job.recipe }
        if let card = viewModel.activeCard { contributorName = card.provenance.photographerName; cameraName = card.provenance.cameraName; isExpanded = false }
        else if let camera = coordinator.detectedCamera?.displayName { cameraName = camera }
        viewModel.sourceDidChange(to: coordinator.sourceURL)
        viewModel.updateSetupSignature(setupSignature)
    }
}

// MARK: - Enhanced Components (matching macOS sophistication)

struct CopyAndVerifyHeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                Text("COPY & VERIFY")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            Text("Copy files to backup destinations with integrity verification")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
        }
    }
}

private struct IpadTransferPlanPreflightCard: View {
    let plan: TransferPlanPresentation

    var body: some View {
        let display = TransferPlanStatusDisplay.make(plan.status)
        let tint = color(for: display.tone)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: display.symbol).font(.system(size: 17, weight: .semibold)).foregroundColor(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(display.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(display.detail).font(.system(size: 13)).foregroundColor(.white.opacity(0.68)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.2), lineWidth: 1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preflight: \(display.title). \(display.detail)")
    }

    private func color(for tone: TransferPlanStatusTone) -> Color {
        switch tone {
        case .success: .green
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

private struct IpadTransferPlanOptionSummary: View {
    let plan: TransferPlanPresentation
    let isQuickMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(plan.optionSummary, id: \.self) { summary in
                        Text(summary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.76))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }
            }

            if isQuickMode {
                Label("Quick mode does not use checksum verification.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .accessibilityLabel("Warning: Quick mode does not use checksum verification")
            }
        }
    }
}

struct EnhancedSourceDestinationView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        ProfessionalSourceCard(coordinator: coordinator)
                            .frame(minWidth: 280, maxWidth: .infinity)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))

                        DestinationsFlowView(coordinator: coordinator)
                            .frame(minWidth: 280, maxWidth: .infinity)
                    }

                    stackedCards
                }
            } else {
                stackedCards
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var stackedCards: some View {
        VStack(spacing: 16) {
            ProfessionalSourceCard(coordinator: coordinator)
            DestinationsFlowView(coordinator: coordinator)
        }
    }
}

// CompactOperationView removed as it is handled by ModularContentView switching to OperationProgressView

struct ProfessionalSourceCard: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("SOURCE FOLDER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Spacer()
                
                if coordinator.sourceURL != nil && !coordinator.isOperationInProgress {
                    Button {
                        coordinator.sourceURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Clear source folder \(coordinator.sourceURL?.lastPathComponent ?? "")")
                    .accessibilityHint("Removes the selected source folder from this transfer.")
                }
            }
            
            // Content
            if let sourceURL = coordinator.sourceURL {
                // Selected state
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sourceURL.lastPathComponent)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            
                            if let folderInfo = coordinator.sourceFolderInfo {
                                HStack(spacing: 8) {
                                    Text("\(folderInfo.formattedFileCount) files")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Text("•")
                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    Text(folderInfo.formattedSize)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Text(sourceURL.path)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(2)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Camera detection badge
                    if let detectedCamera = coordinator.detectedCamera {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                            Text(detectedCamera.displayName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.15))
                        )
                    }
                }
            } else {
                // Empty state
                Button {
                    Task { 
                        await coordinator.selectSourceFolder()
                    }
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.3))
                        
                        VStack(spacing: 4) {
                            Text("Select Source Folder")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Text("Choose the folder containing files to copy")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(coordinator.sourceURL != nil ? Color.green.opacity(0.05) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(coordinator.sourceURL != nil ? Color.green.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct DestinationsFlowView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("DESTINATIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1.2)
                
                if !coordinator.destinationURLs.isEmpty {
                    Text("\(coordinator.destinationURLs.count) selected")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            if coordinator.destinationURLs.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("Add backup drives")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Button("Add Destinations...") {
                        Task { await coordinator.addDestinationFolder() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            } else {
                // Vertical list of destination cards (for side-by-side layout)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(coordinator.destinationURLs, id: \.self) { url in
                            CompactDestinationCard(url: url, coordinator: coordinator)
                        }
                        
                        // Add more button
                        if !coordinator.isOperationInProgress {
                            Button {
                                Task { await coordinator.addDestinationFolder() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                    Text("Add More...")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

struct EnhancedDestinationCard: View {
    let url: URL
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 10) {
            // Header with remove button
            HStack {
                Spacer()
                if !coordinator.isOperationInProgress {
                    Button {
                        coordinator.removeDestinationFolder(url)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Remove destination \(url.lastPathComponent)")
                    .accessibilityHint("Removes \(url.lastPathComponent) from the backup destinations.")
                }
            }
            .frame(height: 14)
            
            // Drive icon
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
            
            // Drive info
            VStack(spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("External Drive")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                
                // Path preview
                Text(url.path)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct CompactDestinationCard: View {
    let url: URL
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 14))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("External Drive")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            if !coordinator.isOperationInProgress {
                Button {
                    coordinator.removeDestinationFolder(url)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Remove destination \(url.lastPathComponent)")
                .accessibilityHint("Removes \(url.lastPathComponent) from the backup destinations.")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct CollapsibleLabelingSection: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "textformat")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    
                    Text("FOLDER LABELING")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Preview when collapsed
                    if !isExpanded && !coordinator.cameraLabelSettings.label.isEmpty {
                        Text("\"\(coordinator.cameraLabelSettings.label)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    Divider().overlay(Color.white.opacity(0.1))
                    
                    VStack(spacing: 16) {
                        // Camera label field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Camera Label")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            
                            TextField(
                                "Enter camera name (e.g., A-Cam, B-Cam)",
                                text: Binding(
                                    get: { coordinator.cameraLabelSettings.label },
                                    set: { coordinator.cameraLabelSettings.label = $0 }
                                )
                            )
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                                .foregroundColor(.white)
                        }
                        
                        // Quick presets (wrapped layout)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Presets")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 60), spacing: 8)
                            ], spacing: 8) {
                                ForEach(["A-Cam", "B-Cam", "C-Cam", "Main", "Audio", "Drone"], id: \.self) { preset in
                                    Button {
                                        coordinator.cameraLabelSettings.label = preset
                                    } label: {
                                        Text(preset)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.orange.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Settings grid
                        VStack(spacing: 12) {
                            HStack(spacing: 16) {
                                // Position
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Position")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    HStack(spacing: 6) {
                                        positionChip(title: "Prefix", position: .prefix)
                                        positionChip(title: "Suffix", position: .suffix)
                                    }
                                }
                                
                                Spacer()
                                
                                // Separator
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Separator")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    HStack(spacing: 4) {
                                        ForEach(CameraLabelSettings.Separator.allCases.prefix(3), id: \.self) { sep in
                                            separatorChip(sep)
                                        }
                                    }
                                }
                            }
                            
                            // Toggles
                            VStack(spacing: 8) {
                                Toggle(
                                    "Auto-number if folder exists",
                                    isOn: Binding(
                                        get: { coordinator.cameraLabelSettings.autoNumber },
                                        set: { coordinator.cameraLabelSettings.autoNumber = $0 }
                                    )
                                )
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))

                                Toggle(
                                    "Group files by camera type in subfolders",
                                    isOn: Binding(
                                        get: { coordinator.cameraLabelSettings.groupByCamera },
                                        set: { coordinator.cameraLabelSettings.groupByCamera = $0 }
                                    )
                                )
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 1.05, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helpers
    private func positionChip(title: String, position: CameraLabelSettings.LabelPosition) -> some View {
        let selected = coordinator.cameraLabelSettings.position == position
        return Button {
            coordinator.cameraLabelSettings.position = position
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(selected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.orange : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
    
    private func separatorChip(_ sep: CameraLabelSettings.Separator) -> some View {
        let selected = coordinator.cameraLabelSettings.separator == sep
        return Button {
            coordinator.cameraLabelSettings.separator = sep
        } label: {
            Text(sep.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(selected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.orange : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

struct CollapsibleVerificationSection: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    
                    Text("VERIFICATION MODE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Preview when collapsed
                    if !isExpanded {
                        HStack(spacing: 6) {
                            Text(coordinator.verificationMode.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green.opacity(0.8))
                            
                            if coordinator.verificationMode.requiresMHL {
                                Text("MHL")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.orange.opacity(0.15))
                                    )
                            }
                        }
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    Divider()
                        .overlay(Color.white.opacity(0.1))
                    
                    VStack(spacing: 8) {
                        ForEach(VerificationMode.allCases, id: \.self) { mode in
                            VerificationModeRow(coordinator: coordinator, mode: mode)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 1.05, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

struct VerificationModeRow: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    let mode: VerificationMode
    
    var body: some View {
        let isSelected = coordinator.verificationMode == mode
        return Button { coordinator.verificationMode = mode } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .green : .white.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if mode.requiresMHL {
                            Text("MHL")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.orange.opacity(0.15))
                                )
                        }
                        
                        Spacer()
                    }
                    
                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                    
                    // Estimated time
                    if let sourceInfo = coordinator.sourceFolderInfo {
                        Text("Estimated time: \(mode.estimatedTime(fileCount: sourceInfo.fileCount))")
                            .font(.system(size: 11))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.green.opacity(0.08) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.green.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StartTransferButtonView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    var plan: TransferPlanPresentation? = nil
    var showsReadinessBanner = true
    var startsProjectTransfer = false

    private var projectStartPresentation: PhotographerStartPresentation {
        coordinator.photographerJobViewModel.startPresentation(
            preflightReady: plan?.canStart ?? coordinator.operationReadinessAssessment.isReady,
            sourceURL: coordinator.sourceURL,
            destinationCount: coordinator.destinationURLs.count,
            verificationMode: coordinator.verificationMode
        )
    }
    
    private var canStartTransfer: Bool {
        (plan?.canStart ?? coordinator.operationReadinessAssessment.isReady) &&
        (!startsProjectTransfer || projectStartPresentation.canStart) &&
        !coordinator.isOperationInProgress
    }
    
    private var buttonText: String {
        if coordinator.isOperationInProgress {
            return "Transfer in Progress..."
        } else if coordinator.sourceURL == nil {
            return "Select Source Folder"
        } else if coordinator.destinationURLs.isEmpty {
            return "Add Backup Destinations"
        } else if startsProjectTransfer, let blocker = projectStartPresentation.blocker {
            return blocker
        } else if startsProjectTransfer {
            return "Start Project Transfer"
        } else {
            return plan?.actionTitle ?? "Start Copy & Verify"
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if showsReadinessBanner && (coordinator.sourceURL != nil || !coordinator.destinationURLs.isEmpty) {
                ReadinessBannerView(assessment: coordinator.operationReadinessAssessment)
            }

            // Transfer summary when ready
            if canStartTransfer, let sourceInfo = coordinator.sourceFolderInfo {
                HStack {
                    Text("Ready to copy \(sourceInfo.formattedFileCount) files (\(sourceInfo.formattedSize)) to \(coordinator.destinationURLs.count) destination\(coordinator.destinationURLs.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }
            }
            
            // Main button
            Button {
                Task {
                    if startsProjectTransfer {
                        _ = await coordinator.startProjectOperation()
                    } else {
                        await coordinator.startOperation()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if coordinator.isOperationInProgress {
                        ProgressView()
                            .scaleEffect(0.9)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: canStartTransfer ? "play.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Text(buttonText)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canStartTransfer ? 
                              LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                              LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(canStartTransfer ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .opacity(canStartTransfer ? 1.0 : 0.6)
            }
            .disabled(!canStartTransfer)
            .buttonStyle(.plain)
        }
    }
}

struct ReadinessBannerView: View {
    let assessment: OperationReadinessAssessment

    private var title: String {
        assessment.isReady ? "Ready Check" : "Needs Attention"
    }

    private var accessibilitySummary: String {
        var parts = [title]
        if !assessment.issues.isEmpty {
            parts.append("Issues: \(assessment.issues.joined(separator: ". "))")
        }
        if !assessment.warnings.isEmpty {
            parts.append("Warnings: \(assessment.warnings.joined(separator: ". "))")
        }
        if let duration = assessment.estimatedDuration, assessment.isReady {
            parts.append("Estimated duration \(duration)")
        }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: assessment.statusIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(assessment.statusColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                if !assessment.issues.isEmpty {
                    readinessMessages(assessment.issues, tint: .red)
                }

                if !assessment.warnings.isEmpty {
                    readinessMessages(assessment.warnings, tint: .orange)
                }

                if assessment.issues.isEmpty && assessment.warnings.isEmpty {
                    Text(assessment.statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let duration = assessment.estimatedDuration, assessment.isReady {
                    Text("Estimated duration \(duration)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(assessment.statusColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(assessment.statusColor.opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func readinessMessages(_ messages: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundColor(tint)
                        .padding(.top, 5)

                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ReportToggleCard: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Generate Reports")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Create PDF & CSV reports after transfer")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $coordinator.reportSettings.makeReport)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(coordinator.reportSettings.makeReport ? Color.blue.opacity(0.05) : Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(coordinator.reportSettings.makeReport ? Color.blue.opacity(0.15) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}
