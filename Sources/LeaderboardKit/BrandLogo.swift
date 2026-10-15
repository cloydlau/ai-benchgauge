#if canImport(SwiftUI) && canImport(ImageIO)
import SwiftUI
import ImageIO

/// The network alone, cropped to its painted edges and kept at its native aspect.
public struct BrandLogo: View {
    public static let aspectRatio = CGFloat(142) / 166
    @Environment(\.colorScheme) private var colorScheme
    private static let bundledImage = loadImage(at:
        Bundle.main.url(forResource: "header-logo", withExtension: "png", subdirectory: "brand")
            ?? Bundle.module.url(forResource: "header-logo", withExtension: "png", subdirectory: "Brand"))
    private let image: CGImage?
    private static let bundledDarkImage = loadImage(at:
        Bundle.main.url(forResource: "header-logo-dark", withExtension: "png", subdirectory: "brand")
            ?? Bundle.module.url(forResource: "header-logo-dark", withExtension: "png", subdirectory: "Brand"))
    private let darkImage: CGImage?

    static func loadImage(at url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public init() { image = Self.bundledImage; darkImage = Self.bundledDarkImage }
    init(image: CGImage?) { self.image = image; darkImage = image }

    public var body: some View {
        if let image = colorScheme == .dark ? darkImage : image {
            Image(decorative: image, scale: 1).resizable().scaledToFit().accessibilityHidden(true)
        }
    }
}
#endif
