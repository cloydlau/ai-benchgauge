import Foundation

/// Data attribution is distinct from the application's software license.
/// The same bundled notice is used by every client, including offline exports.
public enum EpochAttribution {
    struct Notice: Decodable, Sendable {
        let credit: String
        let sourceURL: String
        let licenseURL: String
        let changes: [String: String]
    }
    // These notices are required distribution resources. Loading remains
    // fail-fast, with the throwing decoder separately verifiable by callers.
    private static let notice = try! load(from: BundledResource.url("EpochAttribution", extension: "json"))
    static func load(from url: URL) throws -> Notice {
        try JSONDecoder().decode(Notice.self, from: Data(contentsOf: url))
    }
    static func localizedChanges(_ changes: [String: String], language: AppLanguage) -> String {
        changes[language.rawValue] ?? changes["en"]!
    }
    public static var credit: String { notice.credit }
    public static var sourceURL: String { notice.sourceURL }
    public static var licenseURL: String { notice.licenseURL }
    public static var links: String { sourceURL + " · " + licenseURL }
    public static func changes(language: AppLanguage) -> String { localizedChanges(notice.changes, language: language) }
    public static func fullText(language: AppLanguage) -> String {
        [credit, links, changes(language: language)].joined(separator: "\n")
    }
}
