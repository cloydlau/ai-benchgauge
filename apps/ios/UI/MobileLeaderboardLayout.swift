import Foundation

/// Uses the live window width, including when a phone unfolds or a window resizes.
struct MobileLeaderboardLayout {
    static let inset: CGFloat = 18
    static let spacing: CGFloat = 12
    static let minimumBoardWidth: CGFloat = 360
    static let maximumContentWidth: CGFloat = 1440

    let contentWidth: CGFloat
    let columns: Int

    init(width: CGFloat, boardCount: Int) {
        contentWidth = min(Self.maximumContentWidth, max(0, width - Self.inset * 2))
        let fitting = Int((contentWidth + Self.spacing) / (Self.minimumBoardWidth + Self.spacing))
        columns = max(1, min(3, boardCount, fitting))
    }

    var usesCube: Bool { columns == 1 }
    var boardWidth: CGFloat {
        (contentWidth - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns)
    }
    var usesCompactColumns: Bool { boardWidth < 500 }
}
