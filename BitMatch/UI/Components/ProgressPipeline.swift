// Views/Components/ProgressPipeline.swift
import SwiftUI

struct ProgressPipeline: View {
    let source: String
    let destination: String
    let copyProgress: Double
    let verifyProgress: Double
    let currentFile: String?
    let speed: String?
    let isActive: Bool
    var stage: PipelineStage = .idle
    var compactMode: Bool = false // New property for compact mode
    
    enum PipelineStage {
        case idle
        case copying
        case verifying
        case completed
        case failed
        
        var color: Color {
            switch self {
            case .idle: return .gray
            case .copying: return .blue
            case .verifying: return .green
            case .completed: return .green
            case .failed: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .idle: return "arrow.right.circle"
            case .copying: return "arrow.right.doc.on.clipboard"
            case .verifying: return "checkmark.shield"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }
    
    private var totalProgress: Double {
        // Combined progress (copy is first 50%, verify is second 50%)
        return (copyProgress * 0.5) + (verifyProgress * 0.5)
    }
    
    var body: some View {
        if compactMode {
            MiniProgressPipeline(
                progress: totalProgress,
                isActive: isActive,
                color: stage.color
            )
        } else {
            SimpleProgressLine(
                progress: totalProgress,
                isActive: isActive,
                color: stage.color,
                stage: stage,
                speed: speed
            )
        }
    }
}

// MARK: - Simple Progress Line Component
struct SimpleProgressLine: View {
    let progress: Double
    let isActive: Bool
    let color: Color
    let stage: ProgressPipeline.PipelineStage
    let speed: String?
    
    var body: some View {
        VStack(spacing: 6) {
            // Main progress line with arrow and embedded status
            HStack(spacing: 8) {
                // Left spacer to center the line
                Spacer()
                    .frame(width: 20)
                
                // Progress line with embedded status
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background line
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 2)
                        
                        // Progress fill
                        if progress > 0 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            color.opacity(0.8),
                                            color
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 2)
                                .animation(.linear(duration: 0.3), value: progress)
                        }
                        
                        // Status info positioned in center of line
                        if isActive || stage == .completed || stage == .failed {
                            HStack(spacing: 6) {
                                Image(systemName: stage.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(stage.color)
                                
                                if let speed = speed, isActive {
                                    Text(speed)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(stage.color)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.8))
                                    .overlay(
                                        Capsule()
                                            .stroke(stage.color.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                            .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.5)
                        }
                    }
                }
                .frame(height: 20) // Increased to accommodate the status overlay
                
                // Arrow at the end
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(stage == .completed ? .green : (isActive ? color : .white.opacity(0.3)))
                
                // Right spacer to center the line
                Spacer()
                    .frame(width: 20)
            }
        }
        .frame(height: 24) // Much smaller than the original 60px
    }
}

// MARK: - Mini Pipeline (for preview/compact view)
struct MiniProgressPipeline: View {
    let progress: Double
    let isActive: Bool
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                
                // Progress
                if progress > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.linear(duration: 0.3), value: progress)
                }
                
                // Glow effect at leading edge
                if isActive && progress > 0 && progress < 1 {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .blur(radius: 4)
                        .offset(x: geometry.size.width * progress - 4)
                        .animation(.linear(duration: 0.3), value: progress)
                }
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Preview Provider
struct ProgressPipeline_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ProgressPipeline(
                source: "A001_CARD",
                destination: "BACKUP_1",
                copyProgress: 0.7,
                verifyProgress: 0.3,
                currentFile: "A001C001_230425_R4K8.mov",
                speed: "245 MB/s",
                isActive: true,
                stage: .copying
            )
            
            ProgressPipeline(
                source: "A001_CARD",
                destination: "BACKUP_2",
                copyProgress: 1.0,
                verifyProgress: 0.6,
                currentFile: "Verifying checksums...",
                speed: "180 MB/s",
                isActive: true,
                stage: .verifying
            )
            
            ProgressPipeline(
                source: "A001_CARD",
                destination: "BACKUP_3",
                copyProgress: 1.0,
                verifyProgress: 1.0,
                currentFile: nil,
                speed: nil,
                isActive: false,
                stage: .completed
            )
        }
        .padding()
        .background(Color.black)
    }
}
