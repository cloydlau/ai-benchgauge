import Foundation

/// Display identity only. The complete terms remain in the repository LICENSE
/// and its byte-identical packaged copies; third-party notices are independent.
public enum ApplicationLicense {
    private struct Document: Decodable, Sendable {
        let name: String
        let shortName: String
    }

    private static let document = try! JSONDecoder().decode(Document.self,
        from: Data(contentsOf: BundledResource.url("ApplicationLicense", extension: "json")))

    public static var name: String { document.name }
    public static var shortName: String { document.shortName }
}
