import SwiftUI

struct PhotographerJobSetupView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var clientName = ""
    @State private var jobName = ""
    @State private var eventDate = Date()
    @State private var photographerName = ""
    @State private var cameraName = ""
    @State private var isExpanded = true
    @State private var customizeLayers = false
    @State private var presetName = ""
    @State private var didHydrate = false

    private var viewModel: PhotographerJobViewModel { coordinator.photographerJobViewModel }
    private var cardNumber: Int {
        return viewModel.proposedCardNumber(cameraName: cameraName)
    }
    private var presentation: PhotographerJobSetupPresentation {
        PhotographerJobSetupPresentation.make(
            clientName: clientName,
            jobName: jobName,
            eventDate: eventDate,
            photographerName: photographerName,
            cameraName: cameraName,
            cardNumber: cardNumber,
            recipe: viewModel.draftRecipe,
            duplicateWarningText: viewModel.duplicateWarning?.message,
            hasSource: coordinator.fileSelectionViewModel.sourceURL != nil,
            isPreparing: viewModel.isPreparing
        )
    }
    private var setupSignature: PhotographerSetupSignature {
        PhotographerSetupSignature(
            clientName: clientName.trimmingCharacters(in: .whitespacesAndNewlines),
            jobName: jobName.trimmingCharacters(in: .whitespacesAndNewlines),
            eventDate: eventDate,
            photographerName: photographerName.trimmingCharacters(in: .whitespacesAndNewlines),
            cameraName: cameraName.trimmingCharacters(in: .whitespacesAndNewlines),
            cardNumber: cardNumber,
            recipe: viewModel.draftRecipe
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            disclosureHeader
            if !isExpanded { duplicateWarning }
            if isExpanded {
                setupFields
                    .disabled(viewModel.isPreparing)
                layerDisclosure
                    .disabled(viewModel.isPreparing)
                packageRoute
                RemoteBackupDestinationView(coordinator: coordinator)
                feedback
                setupAction
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
        )
        .onAppear(perform: hydrateOnce)
        .onChange(of: setupSignature) { _, signature in
            viewModel.updateSetupSignature(signature)
        }
        .onChange(of: viewModel.isPreparing) { wasPreparing, isPreparing in
            if wasPreparing, !isPreparing, viewModel.activeCardDraft != nil {
                customizeLayers = false
                isExpanded = false
            }
        }
        .onChange(of: coordinator.fileSelectionViewModel.sourceCameraLabel) { _, label in
            if cameraName.isEmpty, let label { cameraName = label }
        }
    }

    private var disclosureHeader: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(DesignSystem.Typography.micro)
                    .foregroundColor(DesignSystem.Colors.info)
                Image(systemName: "camera.fill")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Photography job")
                        .font(DesignSystem.Typography.heading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    if !isExpanded {
                        Text(presentation.collapsedSummary)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(presentation.presetTitle)
                    .font(DesignSystem.Typography.micro)
                    .foregroundColor(DesignSystem.Colors.success)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(Capsule().fill(DesignSystem.Colors.accentMuted))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse photography job setup" : "Expand photography job setup")
        .accessibilityValue(presentation.collapsedSummary)
    }

    private var setupFields: some View {
        Grid(alignment: .leading, horizontalSpacing: DesignSystem.Spacing.sm, verticalSpacing: DesignSystem.Spacing.sm) {
            GridRow {
                setupTextField("Client", text: $clientName, prompt: "Smith")
                setupTextField("Job name", text: $jobName, prompt: "Smith Wedding")
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    fieldLabel("Date")
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("Event date")
                }
            }
            GridRow {
                setupTextField("Photographer", text: $photographerName, prompt: "Mike")
                setupTextField("Camera", text: $cameraName, prompt: "Sony A7 IV")
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    fieldLabel("Card")
                    Text(String(format: "%03d", cardNumber))
                        .font(DesignSystem.Typography.mono)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .fill(DesignSystem.Colors.surfaceElevated)
                        )
                        .accessibilityLabel("Card number \(cardNumber)")
                }
            }
        }
    }

    private var layerDisclosure: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    customizeLayers.toggle()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: customizeLayers ? "chevron.down" : "chevron.right")
                        .font(DesignSystem.Typography.micro)
                    Text("Customize layers").font(DesignSystem.Typography.body)
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(customizeLayers ? "Collapse folder layer customization" : "Expand folder layer customization")
                Spacer()
                Picker("Preset", selection: Binding(
                    get: { viewModel.draftRecipe.id },
                    set: { viewModel.selectPreset(id: $0) }
                )) {
                    Text("Wedding").tag(FolderRecipe.wedding.id)
                    ForEach(viewModel.presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                .accessibilityLabel("Folder preset")
            }

            if customizeLayers {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(Array(viewModel.draftRecipe.layers.enumerated()), id: \.element.id) { index, layer in
                        layerRow(layer, index: index)
                    }
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        TextField("Preset name", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Preset name")
                        Button("Save as preset") {
                            viewModel.saveDraftAsPreset(name: presetName)
                            if viewModel.lastError == nil { presetName = "" }
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityHint("Saves the current folder layer order and enabled layers")
                    }
                }
                .padding(.leading, DesignSystem.Spacing.lg)
            }
        }
    }

    private var packageRoute: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text("Package route")
                    .font(DesignSystem.Typography.micro)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text(presentation.pathPreview)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.background.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Package route: \(presentation.pathPreview)")
    }

    @ViewBuilder
    private var feedback: some View {
        duplicateWarning
        if let setupError = viewModel.preparationError {
            Label(setupError, systemImage: "exclamationmark.circle.fill")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.error)
        } else if !presentation.blockers.isEmpty {
            Text(presentation.blockers.joined(separator: ". ") + ".")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var duplicateWarning: some View {
        if let warning = presentation.duplicateWarningText,
           let linkTitle = presentation.duplicateLinkTitle,
           let earlierID = viewModel.duplicateWarning?.priorCardIngestID {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(warning)
                Button(linkTitle) { viewModel.focusCardIngest(id: earlierID) }
                    .buttonStyle(.link)
                    .accessibilityHint("Moves focus to the earlier card ingest row")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.warning)
        }
    }

    private var setupAction: some View {
        HStack {
            if viewModel.isPreparing {
                ProgressView().controlSize(.small)
                Text("Preparing card…")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Button("Cancel") {
                    viewModel.cancelPreparingDraftCard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Stops source analysis and keeps this card setup available")
            }
            Spacer()
            if let state = viewModel.activeCard?.localState,
               state == .locallySafe || state == .issues || state == .cancelled {
                Button("Set up next card") {
                    viewModel.resetForNextCard()
                    isExpanded = true
                }
                .accessibilityHint("Clears the finished card and opens setup for the next card")
            } else {
                Button("Set up card", action: setUpCard)
                    .disabled(!presentation.canSetUpCard)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Analyzes the selected source and prepares its job package")
            }
        }
    }

    private func layerRow(_ layer: FolderLayer, index: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Toggle(layer.kind.title, isOn: Binding(
                get: { viewModel.draftRecipe.layers.first { $0.id == layer.id }?.isEnabled ?? false },
                set: { viewModel.setDraftLayer(layer.id, isEnabled: $0) }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button { viewModel.moveDraftLayer(layer.id, direction: .up) } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .accessibilityLabel("Move \(layer.kind.title) layer up")
            Button { viewModel.moveDraftLayer(layer.id, direction: .down) } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.plain)
            .disabled(index == viewModel.draftRecipe.layers.count - 1)
            .accessibilityLabel("Move \(layer.kind.title) layer down")
        }
        .font(DesignSystem.Typography.caption)
    }

    private func setupTextField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            fieldLabel(label)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(DesignSystem.Typography.micro)
            .foregroundColor(DesignSystem.Colors.textTertiary)
    }

    private func setUpCard() {
        guard presentation.canSetUpCard,
              let sourceURL = coordinator.fileSelectionViewModel.sourceURL else { return }
        viewModel.startPreparingDraftCard(sourceURL: sourceURL, setupSignature: setupSignature)
    }

    private func hydrateOnce() {
        guard !didHydrate else { return }
        didHydrate = true
        if let job = viewModel.activeJob {
            clientName = job.clientName
            jobName = job.jobName
            eventDate = job.eventDate
            viewModel.draftRecipe = job.recipe
        }
        if let card = viewModel.activeCard {
            photographerName = card.provenance.photographerName
            cameraName = card.provenance.cameraName
            isExpanded = false
        } else if let label = coordinator.fileSelectionViewModel.sourceCameraLabel {
            cameraName = label
        }
        viewModel.sourceDidChange(to: coordinator.fileSelectionViewModel.sourceURL)
        viewModel.updateSetupSignature(setupSignature)
    }
}

private extension FolderLayerKind {
    var title: String {
        switch self {
        case .dateAndJob: return "Date and job"
        case .originals: return "Originals"
        case .photographer: return "Photographer"
        case .camera: return "Camera"
        case .cardNumber: return "Card number"
        }
    }
}
