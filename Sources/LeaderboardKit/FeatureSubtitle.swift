#if canImport(SwiftUI)
import SwiftUI

/// Style the separator inside one text run to preserve spacing and accessibility.
public struct FeatureSubtitle: View {
    public let language: AppLanguage
    public init(language: AppLanguage) { self.language = language }

    public var body: some View {
        var text = AttributedString(AppFeatureCopy.subtitle(language: language))
        if let separator = text.range(of: "&") {
            text[separator].foregroundColor = Color.secondary.opacity(0.55)
        }
        return Text(text)
    }
}
#endif
