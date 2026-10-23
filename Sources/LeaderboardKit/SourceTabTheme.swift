import Foundation

/// Source identities, rather than segment positions, select the shared mobile palette.
public enum SourceTabTheme {
    public struct Palette: Decodable, Equatable, Sendable {
        public let background: String
        public let foreground: String
    }
    private struct Variants: Decodable, Sendable {
        let light: Palette
        let dark: Palette
    }
    private struct Source: Decodable, Sendable {
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
        if let source = catalog.sources.first(where: { $0.kinds.contains(kind.rawValue) }) {
            return dark ? source.dark : source.light
        }
        return dark ? catalog.fallback.dark : catalog.fallback.light
    }
}
