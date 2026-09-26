// DockTile.swift - Transfer progress and the verdict on the Mac Dock icon.
import AppKit
import Combine
import SwiftUI
import BitMatchEngine

/// What the Dock icon shows. While a transfer runs, a ring and a centered
/// percentage; when it ends, the verdict, kept until the next transfer so
/// it is still there when you come back to the Mac.
enum DockTileState: Equatable {
    /// The normal app icon.
    case appIcon
    /// `percent` is 0...100, whole numbers.
    case running(percent: Int)
    case paused(percent: Int)
    /// Every file on every backup verified: the card is safe to erase.
    case verified
    /// Finished, but something needs a look (not verified, or issues).
    case needsReview
    case failed

    static func make(state: OperationState, fraction: Double?) -> DockTileState {
        let percent = Int((min(max(fraction ?? 0, 0), 1) * 100).rounded(.down))
        switch state {
        case .idle, .notStarted, .cancelled:
            return .appIcon
        case .inProgress, .copying, .verifying, .resuming:
            return .running(percent: percent)
        case .paused:
            return .paused(percent: percent)
        case .completed(let info):
            // Green only for a real success (Promise 2).
            return info.success ? .verified : .needsReview
        case .failed:
            return .failed
        }
    }
}

/// Keeps `NSApp.dockTile` in step with the coordinator.
@MainActor
final class DockTileController {
    private let coordinator: SharedAppCoordinator
    private var cancellables: Set<AnyCancellable> = []
    private var shown: DockTileState = .appIcon

    init(coordinator: SharedAppCoordinator) {
        self.coordinator = coordinator
        coordinator.operationStatePublisher
            .combineLatest(coordinator.liveProgress.$progress)
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] state, progress in
                self?.show(DockTileState.make(state: state, fraction: progress?.overallProgress))
            }
            .store(in: &cancellables)
    }

    private func show(_ state: DockTileState) {
        guard state != shown else { return }
        shown = state
        let tile = NSApp.dockTile
        if state == .appIcon {
            tile.contentView = nil
        } else {
            let view = NSHostingView(rootView: DockTileView(state: state))
            view.frame = NSRect(origin: .zero, size: tile.size)
            tile.contentView = view
        }
        tile.display()
    }
}

/// Drawn in the app icon's own look: the dark rounded tile, with the ring
/// in the icon's blue-to-green line.
struct DockTileView: View {
    let state: DockTileState

    private static let blue = Color(red: 0.34, green: 0.62, blue: 1.0)
    private static let green = Color(red: 0.35, green: 0.86, blue: 0.55)
    private static let amber = Color(red: 1.0, green: 0.68, blue: 0.25)
    private static let red = Color(red: 1.0, green: 0.38, blue: 0.34)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let tile = side * 0.82
            ZStack {
                RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.19), Color(white: 0.09)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: side * 0.008)
                    )
                    .frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.35), radius: side * 0.02, y: side * 0.012)
                ring(diameter: tile * 0.72, width: tile * 0.075)
                center(size: tile)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private func ring(diameter: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: width)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(ringStyle, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private func center(size: CGFloat) -> some View {
        switch state {
        case .running(let percent), .paused(let percent):
            VStack(spacing: size * 0.005) {
                Text("\(percent)")
                    .font(.system(size: size * (percent == 100 ? 0.25 : 0.3), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(isPaused ? "PAUSED" : "%")
                    .font(.system(size: size * 0.09, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .verified:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.3, weight: .heavy))
                .foregroundStyle(Self.green)
        case .needsReview:
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 0.32, weight: .heavy))
                .foregroundStyle(Self.amber)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: size * 0.28, weight: .heavy))
                .foregroundStyle(Self.red)
        case .appIcon:
            EmptyView()
        }
    }

    private var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    private var ringFraction: CGFloat {
        switch state {
        case .running(let percent), .paused(let percent): CGFloat(percent) / 100
        case .verified, .needsReview, .failed: 1
        case .appIcon: 0
        }
    }

    private var ringStyle: AnyShapeStyle {
        switch state {
        case .running, .appIcon:
            AnyShapeStyle(AngularGradient(colors: [Self.blue, Self.green, Self.blue], center: .center))
        case .paused: AnyShapeStyle(Color.white.opacity(0.45))
        case .verified: AnyShapeStyle(Self.green)
        case .needsReview: AnyShapeStyle(Self.amber)
        case .failed: AnyShapeStyle(Self.red)
        }
    }
}
