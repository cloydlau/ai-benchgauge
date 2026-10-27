import SwiftUI
import LeaderboardKit

public enum LeaderboardSwitchStyle: String, CaseIterable, Sendable {
    case cube, slide, fade
    public init(saved: String?) { self = saved.flatMap(Self.init(rawValue:)) ?? .cube }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .cube: language.text("Cube", "魔方")
        case .slide: language.text("Slide", "滑动")
        case .fade: language.text("Crossfade", "淡入淡出")
        }
    }
    func subtitle(_ language: AppLanguage) -> String {
        switch self {
        case .cube: language.text("Depth & rotation", "立体翻转")
        case .slide: language.text("Smooth & direct", "顺滑推进")
        case .fade: language.text("Soft & subtle", "轻柔交融")
        }
    }
}

@MainActor
final class LeaderboardCubeState: ObservableObject {
    @Published var position: Double
    @Published var face = 0
    @Published var origin = 0
    @Published var direction = 1
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
    init(position: Double = 0) { self.position = position; origin = Int(position.rounded()) }

    /// Rebase a completed wrap without animating back through the other boards.
    func finishTurn(_ serial: Int? = nil) {
        if let serial, serial != turnSerial { return }
        turnSerial += 1
        position = Double(face)
        origin = face
        direction = 1
        dragging = false
        turning = false
    }

    func beginEntrance(reduceMotion: Bool) -> Int? {
        guard !entrancePlayed, !dragging, !turning else { return nil }
        entrancePlayed = true
        entranceSerial += 1
        entranceActive = true
        entranceHintVisible = true
        entranceProgress = 0
        origin = face
        direction = face == 0 ? 1 : -1
        position = reduceMotion ? Double(face) : Double(face) + (face == 0 ? 0.06 : -0.06)
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
    static let contentTopInset: CGFloat = 48
    @Published private(set) var sourceTabsOffset: CGFloat = 0
    @Published private(set) var canReturnToTop = false
    private(set) var rank: Int?
    private(set) var columnHeaderHeight: CGFloat = 0
    private(set) var comparisonRowHeight: CGFloat = 44

    func update(frames: [Int: LeaderboardRankFrame], height: CGFloat) {
        let offset = min(Self.contentTopInset, max(0, Self.contentTopInset - (frames[0]?.minY ?? Self.contentTopInset)))
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

/// Adjacent source faces. Horizontal intent is required so a vertical leaderboard
/// scroll never turns the cube; predicted travel permits short, quick flicks.
enum LeaderboardCube {
    enum DragAxis { case undecided, horizontal, vertical }

    static func dragAxis(current: DragAxis, x: Double, y: Double) -> DragAxis {
        guard current == .undecided else { return current }
        if isHorizontal(x: x, y: y) { return .horizontal }
        return abs(y) >= 8 ? .vertical : .undecided
    }
    static func position(face: Int, translation: Double, width: Double, count: Int = 2) -> Double {
        guard width > 0, count > 0 else { return Double(face) }
        return min(Double(face + 1), max(Double(face - 1), Double(face) - translation / width))
    }
    static func destination(face: Int, translation: Double, predicted: Double, width: Double, count: Int = 2) -> Int {
        let travel = abs(predicted) > abs(translation) ? predicted : translation
        let target = Int(position(face: face, translation: travel, width: width, count: count).rounded())
        return min(face + 1, max(face - 1, target))
    }
    static func normalized(_ face: Int, count: Int) -> Int {
        let count = max(1, count)
        return ((face % count) + count) % count
    }
    /// Explicit source tab taps take the shortest route; boundary swipes navigate categories.
    static func target(face: Int, destination: Int, count: Int) -> Int {
        let target = normalized(destination, count: count)
        let distance = target - face
        return abs(distance) * 2 > count ? target + (distance > 0 ? -count : count) : target
    }
    static func navigation(category: Int, destination: Int, counts: [Int]) -> (category: Int, face: Int) {
        if destination < 0 {
            let previous = normalized(category - 1, count: counts.count)
            return (previous, counts[previous] - 1)
        }
        if destination >= counts[category] { return (normalized(category + 1, count: counts.count), 0) }
        return (category, destination)
    }
    /// Keep outgoing/incoming hosts on fixed adjacent sides throughout a turn.
    /// Two-source categories need this direction to disambiguate the same neighbour.
    static func renderedFace(_ face: Int, origin: Int, direction: Int, count: Int) -> Int {
        if face == origin { return origin }
        return face == normalized(origin + direction, count: count) ? origin + direction : origin + direction * 2
    }
    /// Map unwrapped cube travel to the actual source tab slots, including short routes.
    static func tabPosition(_ position: Double, origin: Int, direction: Int, count: Int) -> Double {
        let progress = min(1, max(0, (position - Double(origin)) * Double(direction)))
        return Double(origin) + Double(normalized(origin + direction, count: count) - origin) * progress
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
    var style: LeaderboardSwitchStyle = .cube
    var shadeTopInset: CGFloat? = nil
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
            .overlayPreferenceValue(LeaderboardRankFrames.self) { frames in
                // Each face can have a different scroll position. Its tab spacer
                // is empty space, so shade only from its own content's top edge.
                Rectangle().fill(.black.opacity(reduceMotion || style != .cube ? 0 : abs(distance) * 0.18))
                    .padding(.top, shadeTopInset ?? max(0, frames[0]?.minY ?? LeaderboardCubeScrollState.contentTopInset))
                    .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(flat || style != .cube ? 0 : distance * 90), axis: (x: 0, y: 1, z: 0),
                              anchor: flat ? .center : (distance < 0 ? .trailing : .leading), perspective: flat || style != .cube ? 0 : 0.65)
            .offset(x: reduceMotion ? 0 : style == .fade ? distance * 12 : style == .slide ? width * distance : flat ? 0 : width * distance)
            .scaleEffect(style == .fade && !reduceMotion ? 1 - min(1, abs(distance)) * 0.025 : 1)
            .opacity(reduceMotion || style == .fade ? max(0, 1 - abs(distance)) : (abs(distance) >= 0.999 ? 0 : 1))
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
