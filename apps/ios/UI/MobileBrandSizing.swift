import CoreText
import Foundation
import LeaderboardKit

/// One scale for both text sizes; the navigation controls and help hit target
/// remain full size. The help glyph is an overlay outside the text's layout.
struct MobileBrandSizing {
    let scale: CGFloat
    var titleFontSize: CGFloat { 30 * scale }
    var subtitleFontSize: CGFloat { 12 * scale }

    init(language: AppLanguage, width: CGFloat, controlsWidth: CGFloat) {
        let titleWidth = BrandTitleMetrics.layoutWidth(language: language, fontSize: 30)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23]
        ] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(CTFontCreateUIFontForLanguage(.system, 12, nil)!, 12, nil, descriptor)
        let captionWidth: CGFloat = language == .english ? 0 : AppFeatureCopy.subtitleRows(language: language).map { row -> CGFloat in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: row,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }.max() ?? 0
        // Keep the absolute help glyph clear of the text, without adding a
        // flex/stack child that can force a third line.
        scale = max(0, min(1, (width - controlsWidth - 6) / titleWidth,
            (width - 18) / max(1, captionWidth)))
    }
}
