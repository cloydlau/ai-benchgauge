import Foundation

/// Official CC BY 4.0 text. Attribution notices stay separate so the about-page
/// license dialog can show the license itself, not the credit or endorsement line.
public enum CCBYLicense {
    struct Document: Decodable, Sendable {
        let canonicalURL: String
        let en: String
        let zh: String
        let zhHant: String

        enum CodingKeys: String, CodingKey {
            case canonicalURL, en, zh
            case zhHant = "zh-Hant"
        }
    }

    // Required distribution resource. Fail at launch if the bundled deed is missing.
    private static let document = try! load(from: BundledResource.url("CC-BY-4.0", extension: "json"))

    static func load(from url: URL) throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    }

    public static var canonicalURL: String { document.canonicalURL }

    public static func text(language: AppLanguage) -> String {
        switch language {
        case .english: document.en
        case .chinese: document.zh
        case .traditionalChinese: document.zhHant
        }
    }
}
