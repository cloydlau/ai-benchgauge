import Foundation

/// Static fallback logos for organizations missing from the parsed
/// leaderboard data (e.g. Arena-only providers such as Tencent).
/// Uses each provider's own site favicon so the URLs are reachable
/// from mainland China (no third-party favicon proxies).
public enum OrganizationLogoCatalog {
    /// Organization keys that have a logo bundled inside the app bundle
    /// under Resources/logos/<key>.(png|ico|jpg). Checked first so logos
    /// work offline and SVG-only marks still render.
    public static func bundledLogoKey(forOrganization organization: String?) -> String? {
        let key = normalized(organization)
        return bundledKeys.contains(key) ? key : nil
    }

    /// Brand theme color (hex) for each provider; one color per company so
    /// the same vendor is easy to spot across both leaderboard columns.
    public static func brandColorHex(forOrganization organization: String?) -> String? {
        brandColors[normalized(organization)]
    }

    private static let brandColors: [String: String] = [
        "anthropic": "#D97757",
        "openai": "#0A0A0A",
        "alibaba": "#615CED",
        "zai": "#3E63DD",
        "spacexai": "#71767B",
        "stepfun": "#1F2937",
        "kimi": "#404040",
        "google": "#4285F4",
        "deepseek": "#4D6BFE",
        "tencent": "#006EFF",
        "meta": "#0081FB",
        "minimax": "#E64646",
        "mistral": "#FA5010",
        "nvidia": "#76B900",
        "thinkingmachines": "#9333EA"
    ]

    public static func logoURL(forOrganization organization: String?) -> URL? {
        guard let urlString = favicons[normalized(organization)] else { return nil }
        return URL(string: urlString)
    }

    private static let bundledKeys: Set<String> = [
        "anthropic", "openai", "alibaba", "zai", "spacexai", "stepfun",
        "kimi", "google", "deepseek", "tencent", "meta", "minimax",
        "mistral", "nvidia", "thinkingmachines"
    ]

    private static let favicons: [String: String] = [
        "anthropic": "https://claude.com/favicon.ico",
        "openai": "https://openai.com/favicon.ico",
        "alibaba": "https://www.alibabacloud.com/favicon.ico",
        "zai": "https://z.ai/favicon.ico",
        "spacexai": "https://x.ai/favicon.ico",
        "stepfun": "https://www.stepfun.com/favicon.ico",
        "kimi": "https://www.kimi.com/favicon.ico",
        "google": "https://ai.google.dev/favicon.ico",
        "deepseek": "https://www.deepseek.com/favicon.ico",
        "tencent": "https://cloud.tencent.com/favicon.ico",
        "meta": "https://about.meta.com/favicon.ico",
        "minimax": "https://www.minimax.io/favicon.ico",
        "mistral": "https://mistral.ai/favicon.ico",
        "nvidia": "https://www.nvidia.com/favicon.ico",
        "thinkingmachines": "https://thinkingmachines.ai/favicon.ico"
    ]

    private static func normalized(_ organization: String?) -> String {
        let words = (organization ?? "")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
        switch words {
        case "moonshot":
            return "kimi"
        default:
            return words
        }
    }
}
