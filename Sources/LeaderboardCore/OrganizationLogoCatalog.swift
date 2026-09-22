import Foundation

/// Bundled marks and row colors for leaderboard organizations.
/// Icons are packaged PNGs (official favicons or Iconify), because remote
/// leaderboard logos are often SVG and will not render in `NSImage`.
/// Purchase-link keys are separate: Alibaba links stay under `alibaba`.
public enum OrganizationLogoCatalog {
    /// Canonical logo and color key.
    /// A present organization always wins. An empty organization falls back
    /// to a Devin model-name prefix, which is the only board that omits it.
    public static func resolvedKey(organization: String?, modelName: String? = nil) -> String? {
        let organizationKey = normalizedKey(organization ?? "")
        if !organizationKey.isEmpty {
            return organizationKey
        }
        let inferred = normalizedKey(modelName ?? "")
        if inferred.hasPrefix("devin") {
            return "devin"
        }
        return nil
    }

    /// Alias-normalized key for an organization string or a remote logo-map key.
    /// Does not infer from model names. Empty input returns an empty string.
    public static func normalizedKey(_ raw: String) -> String {
        let words = raw
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
        switch words {
        case "moonshot", "moonshotai":
            return "kimi"
        case "xai":
            return "spacexai"
        case "alibaba", "alibabaath", "qwen":
            return "qwen"
        case "bytedanceseed":
            return "bytedance"
        case "lumaai", "lumalabs":
            return "luma"
        default:
            return words
        }
    }

    /// Organization keys that have a logo bundled under Resources/logos/<key>.png.
    public static func bundledLogoKey(forOrganization organization: String?, modelName: String? = nil) -> String? {
        guard let key = resolvedKey(organization: organization, modelName: modelName),
              bundledKeys.contains(key) else { return nil }
        return key
    }

    /// Theme color for the row wash and 3px bar.
    /// Colored marks use a hex from the bundled logo, or the company's published
    /// theme when the mark is the black form of that color. Black and white
    /// marks stay achromatic; dark menus flip those to white instead of
    /// inventing a hue to keep the bar visible.
    public static func brandColorHex(forOrganization organization: String?, modelName: String? = nil) -> String? {
        guard let key = resolvedKey(organization: organization, modelName: modelName) else { return nil }
        return brandColors[key]
    }

    /// Black, white, or gray ink. Channel spread, so a near-black mark is not
    /// treated as a hue.
    public static func isAchromaticHex(_ hex: String) -> Bool {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return false }
        let r = Int((rgb >> 16) & 0xFF)
        let g = Int((rgb >> 8) & 0xFF)
        let b = Int(rgb & 0xFF)
        return max(r, g, b) - min(r, g, b) <= 24
    }

    /// Light menus use the stored ink. Dark menus use white for achromatic
    /// marks, the other color of a black logo.
    public static func displayBrandColorHex(_ hex: String, isDark: Bool) -> String {
        isDark && isAchromaticHex(hex) ? "#FFFFFF" : hex
    }

    public static func logoURL(forOrganization organization: String?, modelName: String? = nil) -> URL? {
        guard let key = resolvedKey(organization: organization, modelName: modelName),
              let urlString = favicons[key] else { return nil }
        return URL(string: urlString)
    }

    private static let brandColors: [String: String] = [
        // Hex sampled from the bundled mark, or the published theme when noted.
        "anthropic": "#D97757",
        "openai": "#10A37F", // published green; the bundled blossom is black
        "qwen": "#623AE7",
        "kimi": "#027AFF", // blue dot on the mark
        "google": "#4285F4",
        "deepseek": "#4D6BFE",
        "tencent": "#0055E9",
        "meta": "#0081FB",
        "minimax": "#E93163",
        "mistral": "#EE792F",
        "nvidia": "#76B900",
        "bytedance": "#3C8CFF",
        "xiaomi": "#FF6900",
        "klingai": "#04A6F0",
        "luma": "#00A2FF",
        "fal": "#EC0648",
        "pixverse": "#9727EF",
        "microsoftai": "#0D91E1",
        // Black or gray ink. Do not substitute a hue.
        "zai": "#2C2C2C",
        "spacexai": "#000000",
        "stepfun": "#111111",
        "krea": "#0C0C0C",
        "ideogram": "#232426",
        "runway": "#000000",
        "blackforestlabs": "#000000",
        "opencode": "#131010",
        "devin": "#000000",
        "reve": "#000000",
        "videorebirth": "#000000",
        "thinkingmachines": "#1C1C1E"
    ]

    private static let bundledKeys: Set<String> = [
        "anthropic", "openai", "qwen", "zai", "spacexai", "stepfun",
        "kimi", "google", "deepseek", "tencent", "meta", "minimax",
        "mistral", "nvidia", "bytedance", "xiaomi", "klingai", "krea",
        "ideogram", "runway", "luma", "blackforestlabs", "fal", "pixverse",
        "microsoftai", "opencode", "devin", "reve", "videorebirth",
        "thinkingmachines"
    ]

    /// Reachable from mainland China. Used only when the bundled PNG is missing.
    private static let favicons: [String: String] = [
        "anthropic": "https://claude.com/favicon.ico",
        "openai": "https://openai.com/favicon.ico",
        "qwen": "https://qwen.ai/favicon.ico",
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
        "bytedance": "https://www.bytedance.com/favicon.ico",
        "xiaomi": "https://www.mi.com/favicon.ico",
        "klingai": "https://klingai.com/favicon.ico",
        "krea": "https://www.krea.ai/favicon.ico",
        "ideogram": "https://ideogram.ai/favicon.ico",
        "runway": "https://runway.com/favicon.ico",
        "luma": "https://lumalabs.ai/favicon.ico",
        "blackforestlabs": "https://bfl.ai/favicon.ico",
        "fal": "https://fal.ai/favicon.ico",
        "pixverse": "https://pixverse.ai/favicon.ico",
        "microsoftai": "https://copilot.microsoft.com/favicon.ico",
        "opencode": "https://opencode.ai/favicon.ico",
        "devin": "https://devin.ai/favicon.ico",
        "reve": "https://reve.com/favicon.ico",
        "thinkingmachines": "https://thinkingmachines.ai/favicon.ico"
    ]
}
