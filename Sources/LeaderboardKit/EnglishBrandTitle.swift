#if canImport(SwiftUI) && canImport(CoreText)
import CoreText
import SwiftUI

/// Preserve the original text frame, advances and baseline while replacing only A.
public struct EnglishBrandTitle: View {
    private let fontSize: CGFloat
    public init(fontSize: CGFloat = 21) { self.fontSize = fontSize }

    public var body: some View {
        let artwork = EnglishBrandArtwork.make(fontSize: fontSize)
        return EnglishBrandLogoLayout(artwork: artwork) {
            Text("AI BenchGauge").font(.custom("SnellRoundhand-Bold", fixedSize: fontSize))
                .lineLimit(1).hidden().accessibilityHidden(true)
            EnglishBrandLetters(artwork: artwork).fill(BrandTitleGradient())
            BrandLogo().frame(width: artwork.initial.width, height: artwork.initial.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI BenchGauge")
        .accessibilityAddTraits(.isStaticText)
    }
}

struct EnglishBrandArtwork: @unchecked Sendable {
    let ink: CGRect
    let initial: CGRect
    let letters: CGPath

    static func make(fontSize: CGFloat) -> Self {
        let font = CTFontCreateWithName("SnellRoundhand-Bold" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: "AI BenchGauge", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        var next = CGRect.zero
        let letters = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var points = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &points)
            CTRunGetStringIndices(run, CFRange(), &indices)
            for index in 0..<count {
                guard let path = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                  tx: points[index].x, ty: ink.maxY - points[index].y)
                if indices[index] == 1 { next = path.boundingBoxOfPath.applying(transform) }
                else if indices[index] > 1 { letters.addPath(path, transform: transform) }
            }
        }
        // Match I's painted top and bottom, preserving the native text position
        // and the visible gap while keeping the mark's aspect ratio.
        let width = next.height * BrandLogo.aspectRatio
        let initial = CGRect(x: next.minX - ChineseBrandLayout.gap - width, y: next.minY,
                             width: width, height: next.height)
        return Self(ink: ink, initial: initial, letters: letters)
    }
}

/// Glyph outlines of every letter except A. The layout places this shape where
/// the hidden text's ink starts, so the outlines land on the same pixels.
private struct EnglishBrandLetters: Shape {
    let artwork: EnglishBrandArtwork
    func path(in rect: CGRect) -> Path { Path(artwork.letters) }
}

private struct EnglishBrandLogoLayout: Layout {
    let artwork: EnglishBrandArtwork
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let text = subviews[0].dimensions(in: proposal)
        let y = text[.firstTextBaseline] - artwork.ink.maxY
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: text.width, height: artwork.ink.height))
        subviews[2].place(at: CGPoint(x: bounds.minX + artwork.initial.minX,
                                     y: bounds.minY + y + artwork.initial.minY),
                          anchor: .topLeading, proposal: .unspecified)
    }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline else { return nil }
        return subviews[0].dimensions(in: proposal)[.firstTextBaseline]
    }
}
#endif
