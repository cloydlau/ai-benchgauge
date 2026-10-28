#if canImport(SwiftUI) && canImport(CoreText)
import SwiftUI

/// The desktop English wordmark shares iOS outlines, spacing and network-A shear.
public struct EnglishBrandTitle: View {
    private let fontSize: CGFloat
    public init(fontSize: CGFloat = 21) { self.fontSize = fontSize }

    public var body: some View {
        MobileBrandTitle(language: .english, fontSize: fontSize)
    }
}
#endif
