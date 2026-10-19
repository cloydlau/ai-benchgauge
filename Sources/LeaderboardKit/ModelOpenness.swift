import Foundation

public enum LeaderboardOpennessFilter: String, CaseIterable, Codable, Sendable {
    case all, open, closed, unknown

    public func matches(_ entry: LeaderboardEntry) -> Bool {
        switch self {
        case .all: true
        case .open: entry.resolvedOpenness == .open
        case .closed: entry.resolvedOpenness == .closed
        case .unknown: entry.resolvedOpenness == nil
        }
    }

    public func title(language: AppLanguage) -> String {
        switch self {
        case .all: language.text("All sources", "全部源码")
        case .open: ModelOpenness.open.title(language: language)
        case .closed: ModelOpenness.closed.title(language: language)
        case .unknown: language.text("Unknown", "未知")
        }
    }
}

/// The leaderboard's open-weight/license classification, not an OSI certification.
/// Missing source metadata stays nil; it must never become a closed-source claim.
public enum ModelOpenness: String, Codable, Equatable, Sendable {
    case open, closed

    public func title(language: AppLanguage) -> String {
        switch self {
        case .open: language.text("Open", "开源")
        case .closed: language.text("Closed", "闭源")
        }
    }

    public static func columnTitle(language: AppLanguage) -> String { language.text("Source", "源码") }
    public static func help(language: AppLanguage) -> String {
        language.text("Uses the source's public-weight/license classification; usage restrictions may apply. — means unavailable or not applicable to a company.",
                      "按来源的公开权重或许可证分类，仍可能有使用限制；— 表示来源未提供或公司聚合行不适用。")
    }

    public static func fromLicense(_ license: String?) -> Self? {
        guard let license else { return nil }
        let key = license.lowercased().filter { $0.isLetter || $0.isNumber }
        if key == "proprietary" { return .closed }
        return openLicenses.contains(key) ? .open : nil
    }

    // Source-declared public-weight licenses, including restricted community licenses.
    // Keep the shared FC parser's list identical (checked by its regression suite).
    public static let openLicenses: Set<String> = [
        "mit", "modifiedmit", "apache20", "kimik3license", "minimaxcommunitylicense",
        "openmdw11", "tencenthunyuancommunity", "gemma", "nvidiaopenmodel", "deepseek",
        "ccbync40", "nvidiaopen", "llama31community", "nvidia", "llama4", "llama",
        "qwen", "llama33", "mistralresearch", "nexusflow", "mrl", "llama31",
        "gemmalicense", "jambaopen", "llama3community", "deepseeklicense",
        "qianwenlicense", "dbrxlicense", "llama2community", "yilicense",
        "ai2impactlowrisk", "noncommercial", "llama32", "ccbyncsa40",
        "falcon180btiilicense", "qwencommunity10", "qwenresearch", "ideogramopenmodel",
        "fluxnoncommerciallicense", "krea2communitylicense", "open",
        "flux1devnoncommerciallicense", "minimaxh3communitylicenseagreement",
        "ltx2communitylicenseagreement"
    ]

    static func fromSource(_ value: [String: Any]) -> Self? {
        if let open = value["isOpenWeights"] as? Bool { return open ? .open : .closed }
        if let url = value["openWeightsUrl"] {
            if url is NSNull { return .closed }
            if let text = url as? String, let url = URL(string: text),
               (url.scheme == "http" || url.scheme == "https"), url.host != nil { return .open }
        }
        return fromLicense(value["license"] as? String)
    }
}

public extension LeaderboardEntry {
    /// Exact identities with a verified public-weight release fill omitted source metadata.
    /// Explicit upstream classifications always win.
    var resolvedOpenness: ModelOpenness? {
        openness ?? LeaderboardBrandPolicy.verifiedModelOpenness[(modelID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
            .flatMap(ModelOpenness.init(rawValue:))
            ?? (modelMetadata?.source == "models.dev" ? modelMetadata?.openWeights.map { $0 ? .open : .closed } : nil)
    }
}
