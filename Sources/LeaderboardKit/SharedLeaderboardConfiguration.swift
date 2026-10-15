import Foundation

public enum SharedLeaderboardConfiguration {
    // Enabled after real OSS writes, shared reads and refresh gating passed.
    // Every platform embeds the same endpoint through the shared Swift library.
    private static let bundledEndpoint: String? = "https://ai-benchgauge-qrwtdokchx.cn-shenzhen.fcapp.run"

    /// One bundled endpoint is used by iOS, macOS and the Windows Swift engine.
    /// A configured service failure must never silently bypass its global gate.
    public static var endpoint: URL? {
        endpoint(value: ProcessInfo.processInfo.environment["BENCHGAUGE_SHARED_ENDPOINT"] ?? bundledEndpoint)
    }

    static func endpoint(value: String?) -> URL? {
        guard let value else { return nil }
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            // Fail closed for a broken deployment configuration, rather than
            // sending an unlimited number of direct origin requests.
            return URL(string: "https://invalid-shared-service.invalid")!
        }
        return url
    }
}
