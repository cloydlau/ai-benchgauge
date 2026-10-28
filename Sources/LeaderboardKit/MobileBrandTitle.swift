#if canImport(SwiftUI) && canImport(CoreText)
import SwiftUI
import Foundation

/// Mobile wordmarks share offline outlines, spacing and A shear with WeChat.
public struct MobileBrandTitle: View {
    let language: AppLanguage
    let fontSize: CGFloat
    public init(language: AppLanguage, fontSize: CGFloat = 21) {
        self.language = language
        self.fontSize = fontSize
    }

    public var body: some View {
        let artwork = MobileBrandArtwork.layout(language: language)
        let scale = fontSize / MobileBrandArtwork.specification.baseSize
        ZStack(alignment: .topLeading) {
            Path(artwork.letters).fill(BrandTitleGradient())
            BrandLogo().frame(width: artwork.layout.logoWidth, height: artwork.layout.logoHeight)
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -artwork.layout.logoShear, d: 1,
                    tx: artwork.layout.logoHeight * artwork.layout.logoShear, ty: artwork.layout.logoTop))
        }
        .frame(width: artwork.layout.width, height: artwork.layout.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: artwork.layout.width * scale, height: artwork.layout.height * scale, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.appName)
        .accessibilityAddTraits(.isStaticText)
    }
}

public enum MobileBrandMetrics {
    public static func layoutWidth(language: AppLanguage, fontSize: CGFloat = 21) -> CGFloat {
        MobileBrandArtwork.layout(language: language).layout.width * fontSize / MobileBrandArtwork.specification.baseSize
    }
    public static func inkHeight(language: AppLanguage, fontSize: CGFloat = 21) -> CGFloat {
        MobileBrandArtwork.layout(language: language).layout.height * fontSize / MobileBrandArtwork.specification.baseSize
    }
}

struct MobileBrandArtwork: @unchecked Sendable {
    struct Glyph: Decodable {
        let commands: [Command]
    }
    struct Command: Decodable {
        enum Operation: String, Decodable { case M, L, Q, C, Z }
        let operation: Operation
        let values: [CGFloat]
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            operation = try container.decode(Operation.self)
            var coordinates: [CGFloat] = []
            while !container.isAtEnd { coordinates.append(try container.decode(CGFloat.self)) }
            let count: Int
            switch operation {
            case .M, .L: count = 2
            case .Q: count = 4
            case .C: count = 6
            case .Z: count = 0
            }
            guard coordinates.count == count else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Incorrect glyph coordinate count")
            }
            values = coordinates
        }
    }
    struct Placement: Decodable {
        let key: String
        let x, y, width, height: CGFloat
    }
    struct Layout: Decodable {
        let width, height, logoWidth, logoHeight, logoTop, logoShear: CGFloat
        let glyphs: [Placement]
    }
    struct Specification: Decodable {
        let baseSize: CGFloat
        let layouts: [String: Layout]
        let glyphs: [String: Glyph]
    }
    static let specification: Specification = {
        // A missing or malformed checked-in resource is a build defect, never a
        // reason to silently fall back to a different font or omit a letter.
        // Packaged Mac apps flatten shared resources without a SwiftPM bundle.
        let url = Bundle.main.url(forResource: "mobile-title", withExtension: "json")
            ?? Bundle.module.url(forResource: "mobile-title", withExtension: "json", subdirectory: "Brand")!
        return try! JSONDecoder().decode(Specification.self, from: Data(contentsOf: url))
    }()
    static let english = make(key: "english")
    static let chinese = make(key: "chinese")
    let layout: Layout
    let letters: CGPath
    let glyphBounds: [CGRect]

    static func layout(language: AppLanguage) -> Self { language == .english ? english : chinese }
    static func make(key: String, specification: Specification = MobileBrandArtwork.specification) -> Self {
        let layout = specification.layouts[key]!
        let letters = CGMutablePath()
        var bounds: [CGRect] = []
        for placement in layout.glyphs {
            let glyph = specification.glyphs[placement.key]!
            let path = CGMutablePath()
            for command in glyph.commands {
                let values = command.values
                switch command.operation {
                case .M: path.move(to: CGPoint(x: values[0], y: values[1]))
                case .L: path.addLine(to: CGPoint(x: values[0], y: values[1]))
                case .Q: path.addQuadCurve(to: CGPoint(x: values[2], y: values[3]), control: CGPoint(x: values[0], y: values[1]))
                case .C: path.addCurve(to: CGPoint(x: values[4], y: values[5]), control1: CGPoint(x: values[0], y: values[1]), control2: CGPoint(x: values[2], y: values[3]))
                case .Z: path.closeSubpath()
                }
            }
            let transform = CGAffineTransform(translationX: placement.x, y: placement.y)
            letters.addPath(path, transform: transform)
            bounds.append(path.boundingBoxOfPath.applying(transform))
        }
        return Self(layout: layout, letters: letters, glyphBounds: bounds)
    }
}
#endif
