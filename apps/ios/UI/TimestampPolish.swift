import SwiftUI
import LeaderboardKit

/// A single reflection across the text, followed by a long idle period.
struct TimestampPolish: ViewModifier {
    let ready: Bool
    let revision: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: CGFloat = -0.45
    private var visualPhase: CGFloat? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let value = ProcessInfo.processInfo.environment["BENCHGAUGE_TIMESTAMP_POLISH_PHASE"].flatMap(Double.init) {
            return -0.45 + value * 1.45
        }
        #endif
        return nil
    }
    private var active: Bool {
        ready && visualPhase == nil && !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.arguments.contains("--reduce-motion")
    }

    func body(content: Content) -> some View {
        content.overlay {
            if ready {
                TimestampPolishBand(phase: visualPhase ?? phase)
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: "\(active):\(revision)") {
            phase = -0.45
            guard active else { return }
            do {
                while !Task.isCancelled {
                    // Paint the offscreen starting position before animating.
                    try await Task.sleep(for: .milliseconds(16))
                    withAnimation(.linear(duration: TimestampPolishSchedule.duration)) { phase = 1 }
                    try await Task.sleep(for: .seconds(TimestampPolishSchedule.duration))
                    phase = -0.45
                    try await Task.sleep(for: .seconds(TimestampPolishSchedule.interval - TimestampPolishSchedule.duration - 0.016))
                }
            } catch { phase = -0.45 }
        }
    }
}

/// Draw inside a fixed canvas: an offscreen band must not expand text geometry.
private struct TimestampPolishBand: View, Animatable {
    var phase: CGFloat
    nonisolated var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: phase * size.width, y: 0, width: size.width * 0.45, height: size.height)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.85), .clear]),
                startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        }
    }
}
