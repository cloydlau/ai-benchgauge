import Foundation

/// Bundled marks and row colors for leaderboard organizations.
/// Icons are packaged PNGs (official favicons or Iconify), because remote
/// leaderboard logos are often SVG and will not render in `NSImage`.
/// Purchase-link keys are separate: Alibaba links stay under `alibaba`.
public enum OrganizationLogoCatalog {
    /// Canonical logo key.
    /// A present organization wins, unless the label is a coding-agent
    /// `Harness - Model` pair and the model belongs to another company.
    /// Otherwise Claude Code - Qwen3.8 Max is painted with Anthropic's mark.
    /// An empty organization falls back to a Devin name prefix, which is the
    /// only board that omits it. That fallback keeps the Devin mark. The row
    /// wash is separate and follows the lead model.
    public static func resolvedKey(organization: String?, modelName: String? = nil) -> String? {
        let organizationKey = normalizedKey(organization ?? "")
        if !organizationKey.isEmpty {
            if let hosted = hostedModelKey(from: modelName), hosted != organizationKey {
                return hosted
            }
            return organizationKey
        }
        let inferred = normalizedKey(modelName ?? "")
        if inferred.hasPrefix("devin") {
            return "devin"
        }
        return nil
    }

    /// The developer of the lead model may differ from the organization
    /// operating a coding harness (including Devin Fusion).
    public static func developerKey(organization: String?, modelName: String? = nil) -> String? {
        hostedModelKey(from: modelName)
            ?? resolvedKey(organization: organization, modelName: modelName)
    }

    /// Brand of the lead model in `Harness - Model`. Nil when the label is
    /// not that shape, or the model family has no bundled mark.
    /// Fusion names a sidekick after `+`; that half must not win.
    private static func hostedModelKey(from modelName: String?) -> String? {
        guard let modelName, let separator = modelName.range(of: " - ") else { return nil }
        var modelHalf = modelName[separator.upperBound...]
        if let plus = modelHalf.range(of: " + ") {
            modelHalf = modelHalf[..<plus.lowerBound]
        }
        let tokens = modelHalf
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        for token in tokens {
            guard let key = modelFamilyKey(for: token), bundledKeys.contains(key) else { continue }
            return key
        }
        return nil
    }

    /// `Qwen3.8` tokenizes to `qwen38`, so a family matches the token or the
    /// token plus a leading digit. Longer families are listed first.
    private static func modelFamilyKey(for token: String) -> String? {
        for (family, key) in modelFamilies {
            if token == family { return key }
            guard token.hasPrefix(family), token.count > family.count else { continue }
            let next = token[token.index(token.startIndex, offsetBy: family.count)]
            if next.isNumber { return key }
        }
        return nil
    }

    private static let modelFamilies: [(family: String, key: String)] = [
        ("deepseek", "deepseek"),
        ("minimax", "minimax"),
        ("stepfun", "stepfun"),
        ("gemini", "google"),
        ("chatgpt", "openai"),
        ("claude", "anthropic"),
        ("fable", "anthropic"),
        ("opus", "anthropic"),
        ("sonnet", "anthropic"),
        ("haiku", "anthropic"),
        ("qwen", "qwen"),
        ("kimi", "kimi"),
        ("grok", "spacexai"),
        ("muse", "meta"),
        ("glm", "zai"),
        ("gpt", "openai")
    ]

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

    /// Theme color for the row wash. Colored marks use their brand hue;
    /// similar blues and cyans vary in lightness instead of changing hue.
    /// Monochrome marks use neutral shades. OpenAI keeps its brand green even
    /// though the bundled blossom is black.
    /// A harness label follows the lead model, not the tool and not the
    /// sidekick after `+`. Devin Fusion therefore uses Claude or OpenAI ink
    /// while the mark stays Devin.
    public static func brandColorHex(forOrganization organization: String?, modelName: String? = nil) -> String? {
        guard let key = developerKey(organization: organization, modelName: modelName) else { return nil }
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

    /// Neutral ink becomes a corresponding light gray in dark mode. Models
    /// sharing a brand get stable lightness variants of that same hue.
    public static func displayBrandColorHex(
        _ hex: String,
        isDark: Bool,
        modelName: String? = nil
    ) -> String {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return hex }
        var channels = [
            Int((rgb >> 16) & 0xFF),
            Int((rgb >> 8) & 0xFF),
            Int(rgb & 0xFF),
        ]
        if isDark && isAchromaticHex(hex) {
            let neutral = 255 - Int(Double(channels.reduce(0, +)) / 3 * 0.7)
            channels = [neutral, neutral, neutral]
        }
        if let modelName {
            let shade = modelShade(for: modelName)
            channels = channels.map { channel in
                shade < 0
                    ? Int((Double(channel) * (1 + shade)).rounded())
                    : Int((Double(channel) + Double(255 - channel) * shade).rounded())
            }
        }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    private static func modelShade(for name: String) -> Double {
        // FNV-1a is stable across launches, unlike Swift's randomized Hashable.
        // Ignore formatting so the same model keeps its shade across sources.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for scalar in name.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            for byte in String(scalar).utf8 {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        return [-0.24, -0.12, 0, 0.12, 0.24][Int(hash % 5)]
    }

    public static func logoURL(forOrganization organization: String?, modelName: String? = nil) -> URL? {
        guard let key = resolvedKey(organization: organization, modelName: modelName),
              let urlString = favicons[key] else { return nil }
        return URL(string: urlString)
    }

    private static let brandColors: [String: String] = [
        // Hues follow the bundled marks or published brand colors. Nearby
        // blues/cyans use lighter or darker values within the same hue family.
        "anthropic": "#D97757",
        "openai": "#10A37F", // published green; the bundled blossom is black
        "qwen": "#623AE7",
        "kimi": "#007CFF", // Kimi brand blue, not its mint/cyan secondary
        "google": "#4285F4",
        "deepseek": "#4D6BFE",
        "tencent": "#0052D9", // darker blue from the mark
        "meta": "#0068D5", // darker shade of Meta blue beside Kimi
        "minimax": "#F21985", // magenta petal, off Fal red
        "mistral": "#F29D38", // orange from the pixel mark
        "nvidia": "#76B900",
        "bytedance": "#3C8CFF",
        "xiaomi": "#FF6900",
        "klingai": "#009DCB", // deeper cyan from the ring
        "luma": "#00C8E8", // cyan face, not the purple face
        "fal": "#EC0648",
        "pixverse": "#A129FF", // violet on the mark, off Qwen
        "microsoftai": "#E24B9A", // ribbon magenta, not the blue
        // These bundled marks are monochrome. Distinguish them by shade.
        "zai": "#3A3A3A",
        "spacexai": "#242424",
        "stepfun": "#505050",
        "krea": "#666666",
        "ideogram": "#404040",
        "runway": "#2C2C2C",
        "blackforestlabs": "#343434",
        "opencode": "#5A5A5A",
        "devin": "#202020",
        "reve": "#484848",
        "videorebirth": "#707070",
        "thinkingmachines": "#606060",
        "github": "#303030"
    ]

    private static let bundledKeys: Set<String> = [
        "anthropic", "openai", "qwen", "zai", "spacexai", "stepfun",
        "kimi", "google", "deepseek", "tencent", "meta", "minimax",
        "mistral", "nvidia", "bytedance", "xiaomi", "klingai", "krea",
        "ideogram", "runway", "luma", "blackforestlabs", "fal", "pixverse",
        "microsoftai", "opencode", "devin", "reve", "videorebirth",
        "thinkingmachines", "github"
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
        "thinkingmachines": "https://thinkingmachines.ai/favicon.ico",
        "github": "https://github.com/favicon.ico"
    ]
}
