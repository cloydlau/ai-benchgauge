#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import SwiftUI

/// Keep Chinese on one bottom-aligned line; fit English rows to the title’s painted edges.
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
            FeatureSubtitleInk(outline: Path(artwork.letters), size: artwork.size).fill(.foreground)
            FeatureSubtitleInk(outline: Path(artwork.symbols), size: artwork.size).fill(.foreground).opacity(0.55)
        }
        .frame(minWidth: artwork.size.width * 0.65, idealWidth: artwork.size.width, maxWidth: artwork.size.width)
        .frame(height: artwork.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppFeatureCopy.subtitle(language: language))
    }
}

private struct FeatureSubtitleInk: Shape {
    let outline: Path
    let size: CGSize
    func path(in rect: CGRect) -> Path {
        outline.applying(FeatureSubtitleArtwork.fittingTransform(size: size, width: rect.width))
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

    static func fittingTransform(size: CGSize, width: CGFloat) -> CGAffineTransform {
        let scale = min(1, max(0, width) / size.width)
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: 0, ty: size.height * (1 - scale))
    }

    func fitted(toWidth width: CGFloat) -> Self {
        var transform = Self.fittingTransform(size: size, width: width)
        let scale = transform.a
        return Self(letters: letters.copy(using: &transform)!, symbols: symbols.copy(using: &transform)!,
            size: CGSize(width: size.width * scale, height: size.height))
    }

    static func make(language: AppLanguage, height: CGFloat) -> Self {
        make(rows: AppFeatureCopy.subtitleRows(language: language), height: height)
    }

    static func make(rows: [String], height: CGFloat) -> Self {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23]
        ] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(CTFontCreateUIFontForLanguage(.system, 12, nil)!, 12, nil, descriptor)
        let lines = rows.enumerated().map { index, row in
            let text = row + (index == rows.count - 1 ? " ?" : "")
            return (text, CTLineCreateWithAttributedString(NSAttributedString(string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])))
        }
        let bounds = lines.map { CTLineGetBoundsWithOptions($0.1, .useGlyphPathBounds) }
        let rowGap = rows.count > 1 ? height * 0.2 : 0
        let inkHeight = bounds.reduce(0) { $0 + $1.height }
        let scale = rows.count > 1 ? (height - rowGap) / inkHeight : 1
        var y = (height - inkHeight * scale - rowGap) / scale
        let letters = CGMutablePath(), symbols = CGMutablePath()
        for (index, pair) in lines.enumerated() {
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
            y += bounds[index].height + rowGap / scale
        }
        return Self(letters: letters, symbols: symbols,
            size: CGSize(width: (bounds.map(\.width).max() ?? 0) * scale, height: height))
    }
}
#endif
