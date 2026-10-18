#if canImport(SwiftUI)
import SwiftUI

/// A background only: names and controls keep the cell's full layout width.
public struct LeaderboardScoreBackground: View {
    private let color: Color
    private let ratio: Double

    public init(color: Color, score: Double, leaderScore: Double?) {
        self.color = color
        ratio = LeaderboardPresentation.scoreFillRatio(score, leaderScore: leaderScore)
    }

    public var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: geometry.size.width * ratio, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
