import Foundation

/// Shared and bundled marks and row colors for leaderboard organizations.
/// Shared service converts source logos to PNG; bundled icons remain available
/// when the source has no logo or the service cannot acquire one.
/// Purchase-link keys are separate: Alibaba links stay under `alibaba`.
public enum OrganizationLogoCatalog {
    /// Canonical logo key.
    /// A present organization wins, unless the label is a coding-agent
    /// `Harness - Model` pair and the model belongs to another company.
    /// Otherwise Claude Code - Qwen3.8 Max is painted with Anthropic's mark.
    /// Missing organizations can reuse a known hosted-model family. A Devin
    /// name prefix keeps the Devin mark; its row wash still follows the lead.
    /// Other ambiguous names do not imply a manufacturer.
    public static func resolvedKey(organization: String?, modelName: String? = nil, modelID: String? = nil) -> String? {
        let organizationKey = normalizedKey(organization ?? "")
        if !organizationKey.isEmpty && !["unknown", "other", "na", "none"].contains(organizationKey) {
            if let hosted = hostedModelKey(from: modelName), hosted != organizationKey {
                return hosted
            }
            return organizationKey
        }
        let inferred = normalizedKey(modelName ?? "")
        if inferred.hasPrefix("devin") {
            return "devin"
        }
        let id = (organization ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (modelID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : ""
        return hostedModelKey(from: modelName)
            ?? LeaderboardBrandPolicy.modelDevelopers[id]
            ?? LeaderboardBrandPolicy.modelDevelopers[(modelName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// The developer of the lead model may differ from the organization
    /// operating a coding harness (including Devin Fusion).
    public static func developerKey(organization: String?, modelName: String? = nil, modelID: String? = nil) -> String? {
        hostedModelKey(from: modelName)
            ?? resolvedKey(organization: organization, modelName: modelName, modelID: modelID)
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

    private static let modelFamilies = LeaderboardBrandPolicy.modelFamilies

    /// Alias-normalized key for an organization string or a remote logo-map key.
    /// Does not infer from model names. Empty input returns an empty string.
    public static func normalizedKey(_ raw: String) -> String {
        let words = raw
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
        return LeaderboardBrandPolicy.aliases[words] ?? words
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

    /// Prefer established brand hues, then shared extracted color, then a stable wash.
    public static func rowBrandColorHex(for entry: LeaderboardEntry) -> String {
        if let brand = entry.brand, brand.key.hasPrefix("model-"),
           brand.validPNGData != nil, brand.colorHex.count == 7, brand.colorHex.first == "#",
           UInt32(brand.colorHex.dropFirst(), radix: 16) != nil { return brand.colorHex }
        if let known = brandColorHex(forOrganization: entry.organization, modelName: entry.name) { return known }
        if let brand = entry.brand,
           brand.key == (resolvedKey(organization: entry.organization, modelName: entry.name, modelID: entry.modelID) ?? ""),
           brand.colorHex.count == 7, brand.colorHex.first == "#",
           UInt32(brand.colorHex.dropFirst(), radix: 16) != nil { return brand.colorHex }
        return fallbackColorHex(for: resolvedKey(organization: entry.organization, modelName: entry.name, modelID: entry.modelID) ?? entry.name)
    }

    /// A provider PNG must not replace a bundled product mark. Explicit model
    /// assets still win, and company standings retain the provider's image.
    /// Returning nil lets each native renderer use its bundled logo fallback.
    public static func rowLogoPNGData(for entry: LeaderboardEntry, isCompany: Bool = false) -> Data? {
        let data = entry.brand?.validPNGData
        guard !isCompany, entry.brand?.key.hasPrefix("model-") != true,
              let key = bundledLogoKey(forOrganization: entry.organization, modelName: entry.name),
              bundledModelMarks.contains(key) else { return data }
        let tokens = entry.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if tokens.contains(where: { modelFamilyKey(for: String($0)) == key }) { return nil }
        return data
    }

    // These bundled images are product marks, rather than manufacturer marks.
    private static let bundledModelMarks = LeaderboardBrandPolicy.bundledModelMarks

    public static func fallbackColorHex(for name: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in normalizedKey(name).utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return ["#607D8B", "#4F6DCD", "#8C6BB1", "#318F7A", "#A5683A", "#B55C7B", "#5A87A1", "#737D3C"][Int(hash % 8)]
    }

    public static func initial(organization: String?, modelName: String) -> String {
        let key = resolvedKey(organization: organization, modelName: modelName)
        let label = organization?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text: String
        if let key { text = !label.isEmpty && normalizedKey(label) == key ? label : key }
        else { text = modelName }
        return text.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
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
