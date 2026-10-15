#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import SwiftUI

/// Uses visible glyph edges for equal spacing and a shared vertical center.
public struct ChineseBrandTitle: View {
    public init() {}

    public var body: some View {
        let layout = ChineseBrandLayout.make()
        let inkBottom = layout.path.boundingBoxOfPath.maxY
        let initial = layout.glyphBounds[0]
        ZStack(alignment: .topLeading) {
            Path(layout.pathWithoutInitial).fill(.foreground)
            BrandLogo().frame(width: initial.width, height: initial.width / BrandLogo.aspectRatio)
                .position(x: initial.midX, y: initial.midY)
        }
            .frame(width: layout.size.width, height: layout.size.height)
            .alignmentGuide(.firstTextBaseline) { _ in layout.baseline }
            .alignmentGuide(.bottom) { _ in inkBottom }
            .accessibilityLabel("AI 天梯")
            .accessibilityAddTraits(.isStaticText)
    }
}

struct ChineseBrandLayout {
    let path: CGPath
    let pathWithoutInitial: CGPath
    let size: CGSize
    let baseline: CGFloat
    let glyphBounds: [CGRect]
    static let gap: CGFloat = 2.5

    static func make() -> Self {
        let system = CTFontCreateUIFontForLanguage(.system, 21, nil)!
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3]
        ] as CFDictionary)
        let latin = CTFontCreateCopyWithAttributes(system, 21, nil, descriptor)
        let chinese = CTFontCreateWithName(BrandFont.chineseName as CFString, 25, nil)
        var paths: [CGPath] = []
        for (index, character) in Array("AI天梯".utf16).enumerated() {
            let font = index < 2 ? latin : chinese
            var code = character
            var glyph: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font, &code, &glyph, 1)
            if let path = CTFontCreatePathForGlyph(font, glyph, nil) { paths.append(path) }
        }
        // Retain the existing header height while centering each visible glyph.
        let height = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }.height
        let combined = CGMutablePath()
        let remainder = CGMutablePath()
        var x: CGFloat = 0
        var bounds: [CGRect] = []
        for (index, path) in paths.enumerated() {
            let box = path.boundingBoxOfPath
            let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                              tx: x - box.minX, ty: height / 2 + box.midY)
            combined.addPath(path, transform: transform)
            if index > 0 { remainder.addPath(path, transform: transform) }
            bounds.append(box.applying(transform))
            x += box.width + gap
        }
        let baseline = baseline(height: height, firstGlyph: paths.first)
        return Self(path: combined, pathWithoutInitial: remainder, size: CGSize(width: x - gap, height: height),
                    baseline: baseline, glyphBounds: bounds)
    }

    static func baseline(height: CGFloat, firstGlyph: CGPath?) -> CGFloat {
        height / 2 + (firstGlyph?.boundingBoxOfPath.midY ?? 0)
    }
}
#endif
