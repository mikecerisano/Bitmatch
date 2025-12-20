// ContentView.swift - Modular iPad interface using component architecture
import SwiftUI

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Transfer Queue Models
struct QueuedTransfer: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let sourceFolderInfo: FolderInfo?
    let destinations: [URL]
    let state: TransferState
    let progress: Double
    let currentFile: String?
    let speed: String?
    let timeRemaining: String?
    var createdAt: Date = Date()
    
    enum TransferState {
        case idle
        case copying
        case verifying
        case completed
        case queued
        
        var icon: String {
            switch self {
            case .idle: return "folder.fill"
            case .copying: return "doc.on.doc.fill"
            case .verifying: return "checkmark.shield.fill"
            case .completed: return "checkmark.circle.fill"
            case .queued: return "clock.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .idle: return .white.opacity(0.5)
            case .copying: return .blue
            case .verifying: return .orange
            case .completed: return .green
            case .queued: return .yellow.opacity(0.8)
            }
        }
        
        var displayName: String {
            switch self {
            case .idle: return "Ready"
            case .copying: return "Copying"
            case .verifying: return "Verifying"
            case .completed: return "Completed"
            case .queued: return "Queued"
            }
        }
    }
}

// MARK: - Main ContentView using Modular Architecture
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    
    var body: some View {
        Group {
            if hSize == .compact {
                PhoneContentView()
            } else {
                ModularContentView()
            }
        }
    }
}
