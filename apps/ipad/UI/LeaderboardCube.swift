import SwiftUI

@MainActor
final class LeaderboardCubeState: ObservableObject {
    @Published var position: Double
    @Published var face = 0
    @Published var dragging = false
    @Published var turning = false
    var turnSerial = 0
    @Published var rank: Int?
    @Published var generation = 0
    init(position: Double = 0) { self.position = position }
}

/// Two adjacent faces. Horizontal intent is required so a vertical leaderboard
/// scroll never turns the cube; predicted travel permits short, quick flicks.
enum LeaderboardCube {
    static func position(face: Int, translation: Double, width: Double) -> Double {
        guard width > 0 else { return Double(face) }
        return min(1, max(0, Double(face) - translation / width))
    }
    static func destination(face: Int, translation: Double, predicted: Double, width: Double) -> Int {
        let travel = abs(predicted) > abs(translation) ? predicted : translation
        return position(face: face, translation: travel, width: width) >= 0.5 ? 1 : 0
    }
    static func visibleRank(_ frames: [Int: LeaderboardRankFrame], height: CGFloat) -> Int? {
        guard height > 0 else { return nil }
        let visible = frames.filter { $0.value.maxY > 0 && $0.value.minY < height }
        return visible.filter { $0.value.minY >= -1 }.keys.min() ?? visible.keys.min()
    }
    static func isHorizontal(x: Double, y: Double) -> Bool { abs(x) > abs(y) * 1.25 }
}

struct CubeFace: AnimatableModifier {
    var position: Double
    let face: Int
    let width: CGFloat
    let reduceMotion: Bool
    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }
    private var distance: Double { Double(face) - position }
    // Keep both UIKit scroll hosts in their ordinary coordinate system when
    // settled. A nonzero perspective matrix at zero degrees can leave native
    // menu hit testing inconsistent with the visibly flat page.
    private var flat: Bool { reduceMotion || abs(distance) < 0.0001 || abs(distance) > 0.9999 }
    func body(content: Content) -> some View {
        content
            .overlay(Color.black.opacity(reduceMotion ? 0 : abs(distance) * 0.18).allowsHitTesting(false))
            .rotation3DEffect(.degrees(flat ? 0 : distance * 90), axis: (x: 0, y: 1, z: 0),
                              anchor: flat ? .center : (face == 0 ? .trailing : .leading), perspective: flat ? 0 : 0.65)
            .offset(x: flat ? 0 : width * distance)
            .opacity(reduceMotion ? 1 - abs(distance) : (abs(distance) >= 0.999 ? 0 : 1))
            .zIndex(1 - abs(distance))
    }
}

struct LeaderboardRankFrame: Equatable, Sendable {
    let minY: CGFloat
    let maxY: CGFloat
}
struct LeaderboardRankFrames: PreferenceKey {
    static var defaultValue: [Int: LeaderboardRankFrame] { [:] }
    static func reduce(value: inout [Int: LeaderboardRankFrame], nextValue: () -> [Int: LeaderboardRankFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { _, right in right })
    }
}
