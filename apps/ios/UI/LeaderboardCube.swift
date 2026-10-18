import SwiftUI

@MainActor
final class LeaderboardCubeState: ObservableObject {
    @Published var position: Double
    @Published var face = 0
    @Published var dragging = false
    @Published var turning = false
    var turnSerial = 0
    // Scroll geometry changes every frame. Only the small overlays observe it;
    // publishing it on the cube would invalidate both boards and the heading.
    let scroll = LeaderboardCubeScrollState()
    @Published var generation = 0
    @Published var entranceProgress: Double = 1
    @Published var entranceActive = false
    @Published var entranceHintVisible = false
    private(set) var entrancePlayed = false
    private var entranceSerial = 0
    init(position: Double = 0) { self.position = position }

    func beginEntrance(reduceMotion: Bool) -> Int? {
        guard !entrancePlayed, !dragging, !turning else { return nil }
        entrancePlayed = true
        entranceSerial += 1
        entranceActive = true
        entranceHintVisible = true
        entranceProgress = 0
        position = reduceMotion ? Double(face) : 0.18
        return entranceSerial
    }
    func isCurrentEntrance(_ serial: Int) -> Bool {
        entranceSerial == serial && entrancePlayed
    }
    func settleEntrance(_ serial: Int) {
        guard isCurrentEntrance(serial) else { return }
        entranceActive = false
    }
    /// Invalidates every suspended animation step before giving control back.
    func finishEntrance(_ serial: Int? = nil) {
        if let serial, !isCurrentEntrance(serial) { return }
        entranceSerial += 1
        entrancePlayed = true
        entranceActive = false
        entranceHintVisible = false
        entranceProgress = 1
        position = Double(face)
    }
}

@MainActor
final class LeaderboardCubeScrollState: ObservableObject {
    @Published private(set) var sourceTabsOffset: CGFloat = 0
    @Published private(set) var canReturnToTop = false
    private(set) var rank: Int?
    private(set) var columnHeaderHeight: CGFloat = 0
    private(set) var comparisonRowHeight: CGFloat = 44

    func update(frames: [Int: LeaderboardRankFrame], height: CGFloat) {
        let offset = min(48, max(0, 48 - (frames[0]?.minY ?? 48)))
        if sourceTabsOffset != offset { sourceTabsOffset = offset }
        let heading = frames[-1]
        columnHeaderHeight = heading.map { $0.maxY - $0.minY } ?? 0
        // Keep the exact comparison position without notifying views as each
        // row passes the pinned header. Only button visibility needs a redraw.
        rank = (frames[0]?.minY ?? -.infinity) >= -1 ? 0
            : LeaderboardCube.visibleRank(frames.filter { $0.key > 0 }, height: height,
                topInset: columnHeaderHeight)
        if let rank, let row = frames[rank] { comparisonRowHeight = row.maxY - row.minY }
        let canReturn = (rank ?? 0) > 1
        if canReturnToTop != canReturn { canReturnToTop = canReturn }
    }

    func reset() {
        rank = nil
        columnHeaderHeight = 0
        comparisonRowHeight = 44
        if sourceTabsOffset != 0 { sourceTabsOffset = 0 }
        if canReturnToTop { canReturnToTop = false }
    }
}

/// Two adjacent faces. Horizontal intent is required so a vertical leaderboard
/// scroll never turns the cube; predicted travel permits short, quick flicks.
enum LeaderboardCube {
    enum DragAxis { case undecided, horizontal, vertical }

    static func dragAxis(current: DragAxis, x: Double, y: Double) -> DragAxis {
        guard current == .undecided else { return current }
        if isHorizontal(x: x, y: y) { return .horizontal }
        return abs(y) >= 8 ? .vertical : .undecided
    }
    static func position(face: Int, translation: Double, width: Double) -> Double {
        guard width > 0 else { return Double(face) }
        return min(1, max(0, Double(face) - translation / width))
    }
    static func destination(face: Int, translation: Double, predicted: Double, width: Double) -> Int {
        let travel = abs(predicted) > abs(translation) ? predicted : translation
        return position(face: face, translation: travel, width: width) >= 0.5 ? 1 : 0
    }
    static func visibleRank(_ frames: [Int: LeaderboardRankFrame], height: CGFloat, topInset: CGFloat = 0) -> Int? {
        guard height > topInset else { return nil }
        let visible = frames.filter { $0.value.maxY > topInset && $0.value.minY < height }
        // Keep even a partially visible row below the pinned header. Advancing
        // to the next whole row can hide its still-visible name on the new face.
        if topInset > 0 { return visible.keys.min() }
        return visible.filter { $0.value.minY >= topInset - 1 }.keys.min() ?? visible.keys.min()
    }
    static func isHorizontal(x: Double, y: Double) -> Bool { abs(x) >= 16 && abs(x) > abs(y) * 1.75 }
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
