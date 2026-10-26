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
                #expect(abs(sizing.titleFontSize / sizing.baseTitleFontSize - sizing.subtitleFontSize / sizing.baseSubtitleFontSize) < 0.0001)
                let heading = MobileBrandMetrics.layoutWidth(language: language, fontSize: sizing.titleFontSize)
                    + sizing.subtitleWidth + sizing.titleCaptionSpacing
                #expect(heading + controls + MobileBrandSizing.controlsSpacing <= width + 0.01)
                #expect(sizing.showsSubtitle == (language != .english))
                let expectedInkHeight: CGFloat = 30 * (language == .english ? 0.8 : 0.85) * sizing.scale
                #expect(abs(MobileBrandMetrics.inkHeight(language: language, fontSize: sizing.titleFontSize) - expectedInkHeight) < 0.001)
                previous = sizing.scale
            }
            #expect(previous == 1)
        }
    }
}
