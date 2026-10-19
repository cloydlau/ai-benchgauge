import CoreText
import Foundation
import LeaderboardKit

/// Fit the title and its two-row caption together, as in the mini-program.
/// Controls and the help hit target keep their native sizes.
struct MobileBrandSizing {
    let scale: CGFloat
    let baseTitleFontSize: CGFloat
    let baseSubtitleFontSize: CGFloat
    private let captionWidth: CGFloat
    let showsSubtitle: Bool
    var titleFontSize: CGFloat { baseTitleFontSize * scale }
    var subtitleFontSize: CGFloat { baseSubtitleFontSize * scale }
    var subtitleWidth: CGFloat { captionWidth * scale }
    var titleCaptionSpacing: CGFloat { showsSubtitle ? 6 * scale : 0 }
    var subtitleHeight: CGFloat { (30 * 0.85 - 3) * scale }
    static let controlsSpacing: CGFloat = 8

    init(language: AppLanguage, width: CGFloat, controlsWidth: CGFloat) {
        showsSubtitle = language != .english
        // Match the mini-program's title ink height relative to its 30pt control.
        let inkHeight: CGFloat = 30 * (showsSubtitle ? 0.85 : 0.8)
        baseTitleFontSize = 32 * inkHeight / BrandTitleMetrics.inkHeight(language: language, fontSize: 32)
        baseSubtitleFontSize = min(11, (inkHeight - 4) / 2)
        let titleWidth = BrandTitleMetrics.layoutWidth(language: language, fontSize: baseTitleFontSize)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23]
        ] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(CTFontCreateUIFontForLanguage(.system, baseSubtitleFontSize, nil)!, baseSubtitleFontSize, nil, descriptor)
        captionWidth = showsSubtitle ? AppFeatureCopy.subtitleRows(language: language).map { row -> CGFloat in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: row,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }.max() ?? 0 : 0
        // The help glyph floats into the existing control gap; it cannot wrap a row.
        let headingWidth = titleWidth + captionWidth + (showsSubtitle ? 6 : 0)
        scale = max(0, min(1, (width - controlsWidth - Self.controlsSpacing) / headingWidth))
    }
}
