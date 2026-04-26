// Views/HorizontalFlowView.swift - Redesigned compact version
import SwiftUI
import UniformTypeIdentifiers

typealias DriveSpeed = FileSelectionViewModel.DriveSpeed

struct HorizontalFlowView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var hoveredDestination: URL?
    @State private var refreshID = UUID()
    @State private var dragHoveredIndex: Int? = nil
    @State private var isSourceTargeted = false
    @State private var isAddDestinationTargeted = false
    @State private var isAddButtonTargeted = false
    
    // Convenience accessors
    private var fileSelection: FileSelectionViewModel { coordinator.fileSelectionViewModel }
    private var progress: ProgressViewModel { coordinator.progressViewModel }
    private var isOperationActive: Bool { coordinator.isOperationInProgress }
    
    var body: some View {
        VStack(spacing: 16) {
            // Compact horizontal flow: Source → Destinations
            HStack(spacing: 16) {
                // Source section (left)
                compactSourceSection
                    .frame(width: 200)
                
                // Arrow connector
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                
                // Destinations section (right, takes remaining space)
                compactDestinationsSection
                    .frame(maxWidth: .infinity)
            }
            .frame(minHeight: 120, maxHeight: 200) // Allow wrapping to second row
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .id(refreshID) // Force refresh when needed
        .onReceive(fileSelection.$sourceURL) { _ in
            refreshID = UUID()
        }
        .onReceive(fileSelection.$destinationURLs) { _ in
            refreshID = UUID()
        }
    }
    
    // MARK: - Compact Source Section
    @ViewBuilder
    private var compactSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourceSectionHeader
            sourceSectionContent
        }
        .onDrop(of: [.fileURL], isTargeted: $isSourceTargeted) { providers, location in
            handleSourceDrop(providers: providers)
        }
    }
    
    @ViewBuilder
    private var sourceSectionHeader: some View {
        Text("SOURCE")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.5))
            .tracking(1.2)
    }
    
    @ViewBuilder
    private var sourceSectionContent: some View {
        if let sourceURL = fileSelection.sourceURL {
            selectedSourceView(sourceURL: sourceURL)
        } else {
            emptySourceView
        }
    }
    
    @ViewBuilder
    private func selectedSourceView(sourceURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceInfoRow(sourceURL: sourceURL)
            cameraDetectionBadge
        }
        .padding(12)
        .background(selectedSourceBackground)
    }
    
    @ViewBuilder
    private func sourceInfoRow(sourceURL: URL) -> some View {
        HStack(spacing: 8) {
            sourceFolderIcon
            sourceDetails(sourceURL: sourceURL)
            Spacer()
            removeSourceButton
        }
    }
    
    @ViewBuilder
    private var sourceFolderIcon: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 16))
            .foregroundColor(.green)
    }
    
    @ViewBuilder
    private func sourceDetails(sourceURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sourceURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            if let cam = fileSelection.sourceCameraLabel, !cam.isEmpty {
                Text(cam)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green.opacity(0.9))
            }
            
            if let info = fileSelection.sourceFolderInfo {
                let videoText = fileSelection.sourceVideoFileCount > 0 ? "\(fileSelection.sourceVideoFileCount) videos" : "\(info.formattedFileCount) files"
                Text("\(videoText) • \(info.formattedSize)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    @ViewBuilder
    private var removeSourceButton: some View {
        if !isOperationActive {
            Button {
                fileSelection.sourceURL = nil
                refreshID = UUID()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var cameraDetectionBadge: some View {
        // Camera type detection not available in current FolderInfo model
        // This feature would need to be implemented through a different mechanism
        EmptyView()
    }
    
    @ViewBuilder
    private var cameraDetectionBackground: some View {
        Capsule()
            .fill(Color.blue.opacity(0.15))
    }
    
    @ViewBuilder
    private var selectedSourceBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
    }
    
    @ViewBuilder
    private var emptySourceView: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(isSourceTargeted ? .green.opacity(0.7) : .white.opacity(0.3))

            Text("Drag source folder here")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSourceTargeted ? .green.opacity(0.8) : .white.opacity(0.5))

            Text("or")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))

            Button("Choose...") {
                selectSourceFolder()
            }
            .buttonStyle(CustomButtonStyle())
            .scaleEffect(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSourceTargeted ? Color.green.opacity(0.6) : Color.white.opacity(0.15),
                            style: StrokeStyle(lineWidth: isSourceTargeted ? 2 : 1, dash: isSourceTargeted ? [] : [6, 4])
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSourceTargeted)
    }
    
    // MARK: - Compact Destinations Section  
    @ViewBuilder
    private var compactDestinationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESTINATIONS")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.2)
            
            if fileSelection.destinationURLs.isEmpty {
                // Empty state
                VStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(isAddDestinationTargeted ? .green.opacity(0.7) : .white.opacity(0.3))

                    Text("Drag backup drives here")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isAddDestinationTargeted ? .green.opacity(0.8) : .white.opacity(0.5))

                    Text("or")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))

                    Button("Add Destinations...") {
                        selectDestinationFolder()
                    }
                    .buttonStyle(CustomButtonStyle())
                    .scaleEffect(0.9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isAddDestinationTargeted ? Color.green.opacity(0.6) : Color.white.opacity(0.15),
                                    style: StrokeStyle(lineWidth: isAddDestinationTargeted ? 2 : 1, dash: isAddDestinationTargeted ? [] : [6, 4])
                                )
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isAddDestinationTargeted)
                .onDrop(of: [.fileURL], isTargeted: $isAddDestinationTargeted) { providers, location in
                    handleAddDestinationDrop(providers: providers)
                }
            } else {
                // Show destinations in a wrapping grid (3 per row, then wrap)
                let gridColumns = [
                    GridItem(.fixed(120), spacing: 8),
                    GridItem(.fixed(120), spacing: 8), 
                    GridItem(.fixed(120), spacing: 8)
                ]
                
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(Array(fileSelection.destinationURLs.enumerated()), id: \.element) { index, destination in
                        compactDestinationCard(for: destination, at: index)
                    }
                    
                    // Add more button
                    if !isOperationActive {
                        Button {
                            selectDestinationFolder()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Text("Add")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .frame(width: 120, height: 70) // Match destination card size
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                isAddButtonTargeted ? Color.green.opacity(0.6) : Color.white.opacity(0.1),
                                                lineWidth: isAddButtonTargeted ? 2 : 1
                                            )
                                    )
                            )
                            .onDrop(of: [.fileURL], isTargeted: $isAddButtonTargeted) { providers, location in
                                handleAddDestinationDrop(providers: providers)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    @ViewBuilder
    private func compactDestinationCard(for url: URL, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                if !isOperationActive {
                    Button {
                        fileSelection.removeDestination(url)
                        refreshID = UUID()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Drive speed and priority info
            let driveSpeed = fileSelection.detectDriveSpeed(for: url)
            let priority = getFastLanePriority(for: url, at: index)
            
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: driveSpeed.icon)
                        .font(.system(size: 7))
                    Text(driveSpeed.rawValue)
                        .font(.system(size: 8))
                }
                .foregroundColor(driveSpeed.color)
                
                if let priorityInfo = priority {
                    Text("•")
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text(priorityInfo.label)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(priorityInfo.color)
                }
            }

            // Available free space
            if let free = fileSelection.formattedAvailableSpace(for: url) {
                Text("Free: \(free)")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(8)
        .frame(width: 120, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            dragHoveredIndex == index ? Color.green.opacity(0.6) : Color.blue.opacity(0.3),
                            lineWidth: dragHoveredIndex == index ? 2 : 1
                        )
                )
        )
        .opacity(isOperationActive && !isDestinationActive(index) ? 0.5 : 1.0)
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { dragHoveredIndex == index },
            set: { isTargeted in dragHoveredIndex = isTargeted ? index : nil }
        )) { providers, location in
            handleDestinationDrop(providers: providers, targetIndex: index)
        }
        .scaleEffect(dragHoveredIndex == index ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: dragHoveredIndex)
    }
    
    // MARK: - Drag & Drop Handling
    private func handleDestinationDrop(providers: [NSItemProvider], targetIndex: Int) -> Bool {
        guard !isOperationActive else { return false }
        loadDroppedDirectories(providers: providers, allowMultiple: false) { urls in
            guard let url = urls.first else { return }
            guard validateDestination(url, replacingIndex: targetIndex) else { return }
            if targetIndex < fileSelection.destinationURLs.count {
                fileSelection.destinationURLs[targetIndex] = url
                refreshID = UUID()
            }
        }
        return true
    }
    
    private func handleSourceDrop(providers: [NSItemProvider]) -> Bool {
        guard !isOperationActive else { return false }
        loadDroppedDirectories(providers: providers, allowMultiple: false) { urls in
            guard let url = urls.first else { return }
            setSourceURL(url)
        }
        return true
    }
    
    private func handleAddDestinationDrop(providers: [NSItemProvider]) -> Bool {
        guard !isOperationActive else { return false }
        loadDroppedDirectories(providers: providers, allowMultiple: true) { urls in
            addDestinationURLs(urls)
        }
        return true
    }

    private func loadDroppedDirectories(
        providers: [NSItemProvider],
        allowMultiple: Bool,
        completion: @escaping ([URL]) -> Void
    ) {
        guard allowMultiple || providers.count == 1 else {
            rejectDrop("Drop one source folder at a time")
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                defer { group.leave() }
                guard let nsURL = object as? NSURL else {
                    return
                }
                let url = nsURL as URL
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else {
                rejectDrop("Could not read dropped folder")
                return
            }
            guard allowMultiple || urls.count == 1 else {
                rejectDrop("Drop one source folder at a time")
                return
            }
            guard DropValidation.directoriesOnly(urls) else {
                rejectDrop(dropRejectionReason(for: urls))
                return
            }
            completion(urls)
        }
    }

    private func setSourceURL(_ url: URL) {
        guard DropValidation.directoriesOnly([url]) else {
            rejectDrop(dropRejectionReason(for: [url]))
            return
        }
        if let conflict = fileSelection.destinationURLs.first(where: {
            SafetyValidator.destinationSafetyIssue(source: url, destination: $0) != nil
        }) {
            rejectDrop("Source conflicts with destination \(conflict.lastPathComponent)")
            return
        }
        fileSelection.sourceURL = url
        refreshID = UUID()
    }

    private func addDestinationURLs(_ urls: [URL]) {
        for url in urls where validateDestination(url, replacingIndex: nil) {
            fileSelection.addDestination(url)
        }
        refreshID = UUID()
    }

    private func validateDestination(_ url: URL, replacingIndex: Int?) -> Bool {
        guard DropValidation.directoriesOnly([url]) else {
            rejectDrop(dropRejectionReason(for: [url]))
            return false
        }

        let existingDestinations = fileSelection.destinationURLs.enumerated()
            .filter { replacingIndex == nil || $0.offset != replacingIndex }
            .map(\.element)

        if existingDestinations.contains(where: { sameLocation($0, url) }) {
            rejectDrop("\(url.lastPathComponent) is already selected")
            return false
        }

        if let sourceURL = fileSelection.sourceURL,
           let issue = SafetyValidator.destinationSafetyIssue(source: sourceURL, destination: url) {
            rejectDrop(issue)
            return false
        }

        return true
    }

    private func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path ==
            rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func dropRejectionReason(for urls: [URL]) -> String {
        if urls.contains(where: { DropValidation.isSystemDirectory($0) }) {
            return "System directories cannot be used"
        }
        return "Only folders can be used here"
    }

    private func rejectDrop(_ reason: String) {
        NotificationCenter.default.post(
            name: .dropRejected,
            object: nil,
            userInfo: ["reason": reason]
        )
    }
    
    // MARK: - Actions
    private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Select Source"
        
        if panel.runModal() == .OK, let url = panel.url {
            setSourceURL(url)
        }
    }
    
    private func selectDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Select Destination"
        
        if panel.runModal() == .OK {
            addDestinationURLs(panel.urls)
        }
    }
    
    // MARK: - Helper Methods
    
    private func isDestinationActive(_ index: Int) -> Bool {
        // In a real implementation, this would check if this specific destination is being processed
        return isOperationActive
    }
    
    // MARK: - Fast Lane Priority Helper
    
    struct FastLanePriorityInfo {
        let label: String
        let icon: String
        let color: Color
    }
    
    private func getFastLanePriority(for url: URL, at index: Int) -> FastLanePriorityInfo? {
        // Only show priority indicators when we have multiple destinations
        guard fileSelection.destinationURLs.count > 1 else { return nil }
        
        // Get all destination speeds to determine ranking
        let destinationsWithSpeeds = fileSelection.destinationURLs.map { dest in
            (url: dest, speed: fileSelection.detectDriveSpeed(for: dest))
        }
        let sortedBySpeed = destinationsWithSpeeds.sorted { $0.speed.estimatedSpeed > $1.speed.estimatedSpeed }
        
        // Find this URL's position in the speed ranking
        guard let urlIndex = sortedBySpeed.firstIndex(where: { $0.url == url }) else { return nil }
        
        switch urlIndex {
        case 0:
            return FastLanePriorityInfo(label: "PRIORITY", icon: "bolt.fill", color: .green)
        case 1 where sortedBySpeed.count > 2:
            return FastLanePriorityInfo(label: "NEXT", icon: "clock.fill", color: .orange)
        default:
            return FastLanePriorityInfo(label: "QUEUED", icon: "pause.fill", color: .gray)
        }
    }
}
