import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - MHL Status Badge
struct MHLStatusBadge: View {
    let isGenerating: Bool
    let isGenerated: Bool
    let fileName: String?
    
    @State private var pulseAnimation = false
    
    var body: some View {
        if isGenerating || isGenerated {
            HStack(spacing: 4) {
                Image(systemName: isGenerated ? "checkmark.seal.fill" : "doc.text.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isGenerated ? .green : .orange)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                
                Text(isGenerated ? "MHL ✓" : "MHL...")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isGenerated ? .green : .orange)
                
                if isGenerated, let name = fileName {
                    Text(name)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 80)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((isGenerated ? Color.green : Color.orange).opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke((isGenerated ? Color.green : Color.orange).opacity(0.3), lineWidth: 0.5)
                    )
            )
            .onAppear {
                if isGenerating {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                        pulseAnimation = true
                    }
                }
            }
            .onChange(of: isGenerating) { _, generating in
                if !generating {
                    pulseAnimation = false
                }
            }
        }
    }
}

// MARK: - Animation Timer Manager
class AnimationTimerManager: ObservableObject {
    @Published var stripeOffset: CGFloat = 0
    @Published var shimmerOffset: CGFloat = -1
    
    private var timerCancellable: AnyCancellable?
    private var shimmerAnimationTask: Task<Void, Never>?
    
    func startAnimation() {
        stopAnimation()  // Ensure clean state
        
        // FIX: Reduced timer frequency from 33 FPS to 10 FPS
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in  // FIX: Use weak self to be extra safe
                guard let self = self else { return }
                withAnimation(.linear(duration: 0.1)) {
                    self.stripeOffset += 6  // Increased increment to compensate for slower timer
                    if self.stripeOffset > 40 {
                        self.stripeOffset = 0
                    }
                }
            }
        
        // Shimmer animation using Task
        shimmerAnimationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                withAnimation(.linear(duration: 2)) {
                    self.shimmerOffset = 2
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
                if !Task.isCancelled {
                    self.shimmerOffset = -1
                }
            }
        }
    }
    
    func stopAnimation() {
        timerCancellable?.cancel()
        timerCancellable = nil
        shimmerAnimationTask?.cancel()
        shimmerAnimationTask = nil
        stripeOffset = 0
        shimmerOffset = -1
    }
    
    deinit {
        stopAnimation()
    }
}

// MARK: - Card View
struct Card<Content: View>: View {
    let title: String?
    var isSelected: Bool = false
    var progress: Double = 0.0
    var isActive: Bool = false
    var currentFile: String? = nil
    var speed: String? = nil
    var timeRemaining: String? = nil
    var showMHLBadge: Bool = false
    var isMHLGenerating: Bool = false
    var isMHLGenerated: Bool = false
    var mhlFileName: String? = nil
    let onDrop: ((URL) -> Void)?
    @ViewBuilder let content: Content

    @State private var isTargeted = false
    @State private var dragScale = 1.0
    @State private var pulseAnimation = false
    @StateObject private var animationManager = AnimationTimerManager()

    init(_ title: String? = nil,
         isSelected: Bool = false,
         progress: Double = 0.0,
         isActive: Bool = false,
         currentFile: String? = nil,
         speed: String? = nil,
         timeRemaining: String? = nil,
         showMHLBadge: Bool = false,
         isMHLGenerating: Bool = false,
         isMHLGenerated: Bool = false,
         mhlFileName: String? = nil,
         onDrop: ((URL) -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.isSelected = isSelected
        self.progress = progress
        self.isActive = isActive
        self.currentFile = currentFile
        self.speed = speed
        self.timeRemaining = timeRemaining
        self.showMHLBadge = showMHLBadge
        self.isMHLGenerating = isMHLGenerating
        self.isMHLGenerated = isMHLGenerated
        self.mhlFileName = mhlFileName
        self.onDrop = onDrop
        self.content = content()
    }

    private var strokeColor: Color {
        if isActive && progress > 0.001 && progress <= 1 {
            return Color.green
        } else if isSelected {
            return Color.green.opacity(0.4)
        } else if isTargeted {
            return Color.green.opacity(0.6)
        } else {
            return Color.white.opacity(0.1)
        }
    }
    
    @ViewBuilder
    private var backgroundLayers: some View {
        ZStack {
            // Base background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
            
            // Progress fill with animated barber pole stripes
            if isActive && progress > 0.001 && progress <= 1 {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ZStack {
                            // Base green fill
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.green.opacity(0.25),
                                            Color.green.opacity(0.20)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            // Animated barber pole stripes
                            if progress < 1.0 {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.clear)
                                    .overlay(
                                        Canvas { context, size in
                                            let stripeWidth: CGFloat = 20
                                            let totalWidth = size.width + size.height
                                            let numberOfStripes = Int(totalWidth / stripeWidth) + 2
                                            
                                            for i in 0..<numberOfStripes {
                                                let xPos = CGFloat(i) * stripeWidth * 2 + animationManager.stripeOffset
                                                
                                                var path = Path()
                                                path.move(to: CGPoint(x: xPos, y: 0))
                                                path.addLine(to: CGPoint(x: xPos + stripeWidth, y: 0))
                                                path.addLine(to: CGPoint(x: xPos + stripeWidth - size.height, y: size.height))
                                                path.addLine(to: CGPoint(x: xPos - size.height, y: size.height))
                                                path.closeSubpath()
                                                
                                                context.fill(path, with: .color(.white.opacity(0.15)))
                                            }
                                        }
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            
                            // Shimmer overlay
                            if progress < 1.0 {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.clear,
                                                Color.green.opacity(0.3),
                                                Color.green.opacity(0.4),
                                                Color.green.opacity(0.3),
                                                Color.clear
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .mask(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .frame(width: 100)
                                            .offset(x: geo.size.width * animationManager.shimmerOffset)
                                    )
                            }
                        }
                        .frame(width: geo.size.width * progress)
                        
                        // Leading edge glow
                        if progress > 0 && progress < 1 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.green.opacity(0.5),
                                            Color.green.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 20)
                                .blur(radius: 8)
                                .offset(x: -10)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .animation(.linear(duration: 0.3), value: progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: isActive) { _, active in
                    if active && progress < 1.0 {  // Only animate if not complete
                        animationManager.startAnimation()
                    } else {
                        animationManager.stopAnimation()
                    }
                }
                .onAppear {
                    // Start animation if already active when view appears
                    if isActive && progress < 1.0 {
                        animationManager.startAnimation()
                    }
                }
            }
            
            // Drag hover effect
            if isTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
            }
        }
    }
    
    @ViewBuilder
    private var progressOverlay: some View {
        if isActive && progress > 0.001 {
            HStack(spacing: 12) {
                // File info
                if let file = currentFile {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 9))
                        Text(file)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundColor(.green.opacity(0.9))
                } else {
                    Text("Processing...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green.opacity(0.9))
                }
                
                Spacer()
                
                // MHL Badge
                if showMHLBadge {
                    MHLStatusBadge(
                        isGenerating: isMHLGenerating,
                        isGenerated: isMHLGenerated,
                        fileName: mhlFileName
                    )
                }
                
                // Speed indicator
                if let speed = speed {
                    Text(speed)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                // Time remaining
                if let time = timeRemaining {
                    Text(time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                // Percentage - ensure we don't show > 100%
                Text("\(min(100, Int(progress * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    
                    Spacer()
                    
                    // Show live progress stats inline with title when active
                    if isActive && progress > 0.001 {
                        progressOverlay
                    }
                }
            }
            
            content
                .padding(.horizontal, 4)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundLayers)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: isActive && progress > 0.001 && progress <= 1 ?
                            [.green, .green.opacity(0.7), .green] :
                            [strokeColor, strokeColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + (360 * min(1, max(0, progress))))
                    ),
                    lineWidth: isActive && progress > 0.001 ? 2.5 : (isTargeted ? 2 : 1)
                )
                .animation(.linear(duration: 0.3), value: progress)
        )
        .scaleEffect(dragScale)
        .scaleEffect(pulseAnimation && progress >= 1.0 ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isTargeted)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragScale)
        .animation(.easeInOut(duration: 0.6).repeatCount(1), value: pulseAnimation)
        .onChange(of: progress) { oldValue, newValue in
            if oldValue < 1.0 && newValue >= 1.0 {
                // Stop animation when complete
                animationManager.stopAnimation()
                // Pulse animation when complete
                withAnimation {
                    pulseAnimation = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    pulseAnimation = false
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let onDrop = onDrop, let provider = providers.first else {
                return false
            }
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                dragScale = 0.98
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dragScale = 1.0
                }
            }
            
            _ = provider.loadObject(ofClass: NSURL.self) { nsurl, error in
                if let url = nsurl as? URL {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                onDrop(url)
                            }
                        }
                    }
                }
            }
            return true
        }
        .onDisappear {
            // Ensure animations are stopped when view disappears
            animationManager.stopAnimation()
        }
    }
}
