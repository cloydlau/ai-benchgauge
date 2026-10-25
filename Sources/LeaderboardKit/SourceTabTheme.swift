import Foundation

/// Source identities, rather than segment positions, select the shared brand palette.
public enum SourceTabTheme {
    public struct Palette: Decodable, Equatable, Sendable {
        public let background: String
        public let foreground: String
        /// Brand text color on the page/card surface, distinct from the tab label.
        public let accent: String
    }
    private struct Variants: Decodable, Sendable {
        let light: Palette
        let dark: Palette
    }
    private struct Source: Decodable, Sendable {
        let id: String
        let kinds: [String]
        let light: Palette
        let dark: Palette
    }
    private struct Catalog: Decodable, Sendable {
        let fallback: Variants
        let sources: [Source]
    }
    private static let catalog = try! JSONDecoder().decode(Catalog.self,
        from: Data(contentsOf: BundledResource.url("SourceTabThemes", extension: "json")))

    public static func palette(for kind: LeaderboardKind, dark: Bool) -> Palette {
        palette(forKindID: kind.rawValue, dark: dark)
    }

    public static func sourceID(for kind: LeaderboardKind) -> String? {
        catalog.sources.first(where: { $0.kinds.contains(kind.rawValue) })?.id
    }

    static func palette(forKindID kindID: String, dark: Bool) -> Palette {
        if let source = catalog.sources.first(where: { $0.kinds.contains(kindID) }) {
            return dark ? source.dark : source.light
        }
        return dark ? catalog.fallback.dark : catalog.fallback.light
    }
}
