#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import SwiftUI

/// Trim native font line boxes so the two rows share the title's painted edges.
public struct FeatureSubtitle: View {
    public let language: AppLanguage
    public let height: CGFloat
    public init(language: AppLanguage, height: CGFloat = 24) {
        self.language = language
        self.height = height
    }

    public var body: some View {
        let artwork = FeatureSubtitleArtwork.make(language: language, height: height)
        ZStack(alignment: .topLeading) {
            Path(artwork.letters).fill(.foreground)
            Path(artwork.symbols).fill(.foreground).opacity(0.55)
        }
        .frame(width: artwork.size.width, height: artwork.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppFeatureCopy.subtitle(language: language))
    }
}

public enum BrandTitleMetrics {
    public static func inkHeight(language: AppLanguage, fontSize: CGFloat = 21) -> CGFloat {
        if language != .english { return ChineseBrandLayout.make().path.boundingBoxOfPath.height * fontSize / 21 }
        let font = CTFontCreateWithName("SnellRoundhand-Bold" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: language.appName,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).height
    }
}

struct FeatureSubtitleArtwork {
    let letters: CGPath
    let symbols: CGPath
    let size: CGSize

    static func make(language: AppLanguage, height: CGFloat) -> Self {
        let rows = AppFeatureCopy.subtitleRows(language: language)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23]
        ] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(CTFontCreateUIFontForLanguage(.system, 12, nil)!, 12, nil, descriptor)
        let lines = [rows[0], rows[1] + " ?"].map { text in
            (text, CTLineCreateWithAttributedString(NSAttributedString(string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])))
        }
        let bounds = lines.map { CTLineGetBoundsWithOptions($0.1, .useGlyphPathBounds) }
        let rowGap = height * 0.2
        let scale = (height - rowGap) / (bounds[0].height + bounds[1].height)
        let letters = CGMutablePath(), symbols = CGMutablePath()
        for (index, pair) in lines.enumerated() {
            let y = index == 0 ? 0 : bounds[0].height + rowGap / scale
            for run in CTLineGetGlyphRuns(pair.1) as! [CTRun] {
                let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                CTRunGetStringIndices(run, CFRange(), &indices)
                for glyph in 0..<count {
                    guard let path = CTFontCreatePathForGlyph(font, glyphs[glyph], nil) else { continue }
                    let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                        tx: (positions[glyph].x - bounds[index].minX) * scale,
                        ty: (y + bounds[index].maxY - positions[glyph].y) * scale)
                    let character = (pair.0 as NSString).character(at: indices[glyph])
                    (character == 38 || character == 63 ? symbols : letters).addPath(path, transform: transform)
                }
            }
        }
        return Self(letters: letters, symbols: symbols,
            size: CGSize(width: max(bounds[0].width, bounds[1].width) * scale, height: height))
    }
}
#endif
