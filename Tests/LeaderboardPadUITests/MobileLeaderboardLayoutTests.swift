import Foundation
import Testing
@testable import LeaderboardPadUI

struct MobileLeaderboardLayoutTests {
    @Test func narrowAndExpandedWindowsUseReadableBoards() {
        for count in [2, 3] {
            for width: CGFloat in [320, 390, 430, 600, 744, 767, 768, 800, 834, 1024, 1140, 1194, 1600] {
                let layout = MobileLeaderboardLayout(width: width, boardCount: count)
                #expect(layout.usesCube == (width < 768))
                #expect(layout.columns <= count)
                if !layout.usesCube { #expect(layout.boardWidth >= 360) }
                #expect(layout.contentWidth <= 1440)
                #expect(layout.usesCompactColumns == (layout.boardWidth < 500))
            }
        }
    }

    @Test func everyResizeRecomputesTheNumberOfColumns() {
        let widths: [CGFloat] = [390, 834, 1194, 834, 390]
        #expect(widths.map { MobileLeaderboardLayout(width: $0, boardCount: 3).columns } == [1, 2, 3, 2, 1])
        #expect(MobileLeaderboardLayout(width: 1194, boardCount: 2).columns == 2)
        #expect(MobileLeaderboardLayout(width: 0, boardCount: 3).usesCube)
    }
}
