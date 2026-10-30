import Foundation

/// Shared marks and row colors for leaderboard organizations.
/// Images travel with the shared snapshot and remain available offline.
/// Purchase-link keys are separate: Alibaba links stay under `alibaba`.
public enum OrganizationLogoCatalog {
    /// The verified Qwen product mark, independent of cached Alibaba company images.
    public static var qwenProductPNGData: Data { LeaderboardBrandPolicy.qwenProductPNG }
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
    /// not that shape, or the model family is unknown.
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
            guard let key = modelFamilyKey(for: token) else { continue }
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

    /// A legacy brand field for these named models may contain the product
    /// icon rather than its manufacturer's icon, even when the keys match.
    static func hasDistinctModelBrand(_ entry: LeaderboardEntry) -> Bool {
        guard let key = developerKey(organization: entry.organization, modelName: entry.name, modelID: entry.modelID),
              LeaderboardBrandPolicy.bundledModelMarks.contains(key) else { return false }
        return entry.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { modelFamilyKey(for: String($0)) == key }
    }

    static func explicitCompanyBrand(_ entry: LeaderboardEntry) -> OrganizationBrand? {
        guard let brand = entry.organizationBrand else { return nil }
        if isKnownProductImage(brand) { return nil }
        if hasDistinctModelBrand(entry), let png = brand.validPNGData, png == entry.brand?.validPNGData { return nil }
        return brand
    }

    static func legacyCompanyBrand(_ entry: LeaderboardEntry) -> OrganizationBrand? {
        guard entry.organizationBrand == nil, !hasDistinctModelBrand(entry), let brand = entry.brand,
              !isKnownProductImage(brand) else { return nil }
        return brand
    }

    /// Match the exact previously distributed model images in old snapshots.
    /// Fingerprints are generated from the shared catalog, not shipped artwork.
    private static func isKnownProductImage(_ brand: OrganizationBrand) -> Bool {
        guard let data = brand.validPNGData,
              let expected = LeaderboardBrandPolicy.productMarkFingerprints[normalizedKey(brand.key)] else { return false }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return "\(data.count):" + String(format: "%016llx", hash) == expected
    }

    /// Alias-normalized key for an organization string or a remote logo-map key.
    /// Does not infer from model names. Empty input returns an empty string.
    public static func normalizedKey(_ raw: String) -> String {
        let words = raw
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined()
        return LeaderboardBrandPolicy.aliases[words] ?? words
    }

    /// Theme color for the row wash. Colored marks use their brand hue;
    /// similar blues and cyans vary in lightness instead of changing hue.
    /// Monochrome marks use neutral shades. OpenAI keeps its brand green even
    /// though the blossom mark is black.
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

    /// Model and company rows use validated images supplied by the shared service.
    /// Company aggregation normally promotes organizationBrand into brand; the
    /// explicit organization brand also supports unaggregated company consumers.
    public static func rowLogoPNGData(for entry: LeaderboardEntry, isCompany: Bool = false) -> Data? {
        if isCompany {
            return [explicitCompanyBrand(entry), legacyCompanyBrand(entry)].compactMap { $0 }
                .filter { !$0.key.hasPrefix("model-") }.compactMap(\.validPNGData).first
        }
        return entry.brand?.validPNGData
    }

    /// Newest valid manufacturer mark wins across all cached boards. A model
    /// mark must never become an account provider's icon. Missing or malformed
    /// marks do not hide a valid mark from another board, including offline data.
    public static func organizationLogoPNGData(in snapshot: LeaderboardSnapshot) -> [String: Data] {
        var images: [String: Data] = [:]
        let boards = snapshot.boards.values.sorted {
            if $0.fetchedAt != $1.fetchedAt { return $0.fetchedAt > $1.fetchedAt }
            return $0.kind.rawValue < $1.kind.rawValue
        }
        for board in boards {
            for entry in board.entries {
                guard let key = resolvedKey(organization: entry.organization, modelName: entry.name, modelID: entry.modelID),
                      images[key] == nil else { continue }
                for brand in [explicitCompanyBrand(entry), legacyCompanyBrand(entry)].compactMap({ $0 }) {
                    guard !brand.key.hasPrefix("model-"), normalizedKey(brand.key) == key,
                          let png = brand.validPNGData else { continue }
                    images[key] = png
                    break
                }
            }
        }
        return images
    }

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

    private static let brandColors: [String: String] = [
        // Hues follow established marks or published brand colors. Nearby
        // blues/cyans use lighter or darker values within the same hue family.
        "anthropic": "#D97757",
        "openai": "#10A37F", // published green; the blossom is black
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
        // These marks are monochrome. Distinguish them by shade.
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

}
