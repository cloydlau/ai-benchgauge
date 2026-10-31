import Foundation

/// The same option descriptions are embedded by every client; families follow the actual selector.
public enum LeaderboardVariantHelp {
    private struct Option: Decodable, Sendable { let detail: [String] }
    private struct Catalog: Decodable, Sendable {
        let heading: [String]
        let options: [String: Option]
        let references: [String: [String]]
    }
    private static let catalog = try! JSONDecoder().decode(Catalog.self,
        from: Data(contentsOf: BundledResource.url("LeaderboardVariantHelp", extension: "json")))

    public static func text(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        let variants = kind.mediaVariants
        guard let base = variants.first else { return "" }
        let index = language == .english ? 0 : language == .chinese ? 1 : 2
        let options = variants.map { option in
            let entry = catalog.options[option.rawValue]!
            return option.mediaVariantTitle(language: language) + "\n" + entry.detail[index]
        }
        return ([catalog.heading[index]] + options + (catalog.references[base.rawValue] ?? []))
            .joined(separator: "\n\n")
    }
}
