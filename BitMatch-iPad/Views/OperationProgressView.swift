// OperationProgressView.swift - Transfer progress display component for iPad
import SwiftUI

struct OperationProgressView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress header
            ProgressHeaderView(coordinator: coordinator)
            
            // Resume seed banner (only when meaningful)
            if let reused = coordinator.progress?.reusedCopies, reused >= 3 {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.yellow)
                    Text("Resuming: \(reused) already present…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.yellow.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.yellow.opacity(0.25), lineWidth: 0.5)
                        )
                )
            }
            
            // Main progress display
            ProgressDisplayView(coordinator: coordinator)
            
            // Transfer controls
            TransferControlsView(coordinator: coordinator)
            
            // Current file info
            if let progress = coordinator.progress {
                CurrentFileInfoView(progress: progress)
            }
            
            // Error summary section
            if coordinator.hasErrors {
                ErrorSummaryView(coordinator: coordinator)
            }
            
            // Queue section (if exists)
            if !transferQueue.isEmpty {
                TransferQueueView(coordinator: coordinator)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var transferQueue: [ProgressQueuedTransfer] {
        // Placeholder for actual queue implementation
        return []
    }
}

// MARK: - Progress Header Component

struct ProgressHeaderView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 8) {
            // Operation title
            Text(coordinator.currentStage.displayName)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            // Operation timing
            if let duration = coordinator.operationDuration {
                Text("Elapsed: \(duration)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            #if os(iOS)
            if ((UserDefaults.standard.object(forKey: "PreventAutoLockDuringTransfer") as? Bool) ?? true) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 12, weight: .bold))
                    Text("Keep Awake On")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.yellow.opacity(0.12)))
            }

            // Background time remaining hint when app is not active
            if coordinator.isInBackground, let remaining = coordinator.backgroundTimeRemainingSeconds, remaining.isFinite, remaining > 0 {
                let minutes = Int(ceil(remaining / 60.0))
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.orange)
                        .font(.system(size: 12, weight: .bold))
                    Text("Background ~\(minutes)m left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            #endif
        }
        .textCase(.none)
    }
}

// MARK: - Progress Display Component

struct ProgressDisplayView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(spacing: 16) {
            // Main progress bar
            VStack(spacing: 8) {
                HStack {
                    Text("Overall Progress")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("\(Int(coordinator.progressPercentage * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                ProgressView(value: coordinator.progressPercentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .scaleEffect(y: 2.0)
            }
            
            // Stats row
            HStack(spacing: 20) {
                if let progress = coordinator.progress {
                    // Files processed
                    StatView(
                        title: "Files",
                        value: "\(progress.filesProcessed)/\(progress.totalFiles)"
                    )
                    
                    if let reused = progress.reusedCopies, reused > 0 {
                        StatView(title: "Reused", value: "\(reused)")
                    }
                    
                    // Speed
                    if let speed = progress.formattedSpeed {
                        StatView(title: "Speed", value: speed)
                    }
                    
                    // Time remaining
                    if let timeRemaining = progress.formattedTimeRemaining {
                        StatView(title: "Remaining", value: timeRemaining)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Stat View Component

struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Transfer Controls Component

struct TransferControlsView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        HStack(spacing: 12) {
            // Pause/Resume button
            if coordinator.canPause {
                Button {
                    Task { await coordinator.pauseOperation() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Pause")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange)
                    )
                }
                .buttonStyle(.plain)
            } else if coordinator.canResume {
                Button {
                    Task { await coordinator.resumeOperation() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Resume")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Cancel button
            Button {
                coordinator.cancelOperation()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.8))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Current File Info Component

struct CurrentFileInfoView: View {
    let progress: OperationProgress
    
    var body: some View {
        if let currentFile = progress.currentFile {
            VStack(alignment: .leading, spacing: 8) {
                Text("CURRENT FILE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    Text(currentFile)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
        }
    }
}

// MARK: - Error Summary Component

struct ErrorSummaryView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                
                Text("ISSUES DETECTED")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1.0)
                
                Spacer()
                
                Text("\(coordinator.errorCount) errors, \(coordinator.warningCount) warnings")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Text("Review errors after completion")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Transfer Queue Component (Placeholder)

struct TransferQueueView: View {
    @ObservedObject var coordinator: SharedAppCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUEUE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .tracking(1.0)
            
            Text("Queue functionality placeholder")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Supporting Types (Temporary)

struct ProgressQueuedTransfer {
    let id = UUID()
    let name: String
}
