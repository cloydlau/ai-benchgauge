#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import SwiftUI

/// Uses visible glyph edges, rather than font side bearings, for equal spacing.
public struct ChineseBrandTitle: View {
    public init() {}

    public var body: some View {
        let layout = ChineseBrandLayout.make()
        Path(layout.path)
            .fill(.foreground)
            .frame(width: layout.size.width, height: layout.size.height)
            .alignmentGuide(.firstTextBaseline) { _ in layout.baseline }
            .accessibilityLabel("AI 天梯")
            .accessibilityAddTraits(.isStaticText)
    }
}

struct ChineseBrandLayout {
    let path: CGPath
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
        let ink = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let combined = CGMutablePath()
        var x: CGFloat = 0
        var bounds: [CGRect] = []
        for path in paths {
            let box = path.boundingBoxOfPath
            let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                              tx: x - box.minX, ty: ink.maxY)
            combined.addPath(path, transform: transform)
            bounds.append(box.applying(transform))
            x += box.width + gap
        }
        return Self(path: combined, size: CGSize(width: x - gap, height: ink.height),
                    baseline: ink.maxY, glyphBounds: bounds)
    }
}
#endif
