import Foundation
import LeaderboardKit
import Testing
@testable import LeaderboardPadUI

struct MobileBrandSizingTests {
    @Test func narrowHeadersScaleBothTitlesAndLeaveTheControlsAndHelpClear() {
        for language in AppLanguage.allCases {
            let controls: CGFloat = language == .english ? 160 : 104
            var previous: CGFloat = 0
            for width: CGFloat in [256, 296, 351, 378, 406, 744, 1000] {
                let sizing = MobileBrandSizing(language: language, width: width, controlsWidth: controls)
                #expect(sizing.scale > 0 && sizing.scale <= 1)
                #expect(sizing.scale >= previous)
                #expect(abs(sizing.titleFontSize / 30 - sizing.subtitleFontSize / 12) < 0.0001)
                #expect(BrandTitleMetrics.layoutWidth(language: language, fontSize: sizing.titleFontSize) + controls + 6 <= width + 0.01)
                previous = sizing.scale
            }
            #expect(previous == 1)
        }
    }
}
