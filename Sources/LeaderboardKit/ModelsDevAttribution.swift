import Foundation

/// Data notices stay available offline, independently of a matched model or network snapshot.
public enum ModelsDevAttribution {
    public static let sourceURL = URL(string: "https://models.dev")!
    public static func credit(language: AppLanguage) -> String {
        language.text("Model information: models.dev", "模型资料：models.dev")
    }
    public static let licenseText = try! readLicense(at: BundledResource.url("ModelsDev-MIT", extension: "txt"))
    static func readLicense(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
