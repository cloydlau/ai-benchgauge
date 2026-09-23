import Foundation

/// Company standings derived from one board's model rows.
///
/// The score is the strongest listed model. A weaker sibling stays in the
/// breakdown and must not pull the company below a rival whose flagship is
/// stronger. Breadth is not a bonus: a longer listing never outranks a
/// stronger flagship, and model count is not a tie-break.
public enum CompanyLeaderboard {
    /// The table has 20 slots. Extra companies would not be visible.
    private static let displayLimit = 20

    /// Shown on the company score. The number is the flagship, not a blend.
    public static let scoreExplanation = "以最强模型分数为准，弱型号不拉低"

    public static func rank(_ entries: [LeaderboardEntry]) -> [CompanyStanding] {
        var grouped: [String: [LeaderboardEntry]] = [:]
        for entry in entries {
            // A non-positive rank is not a board position.
            guard entry.rank > 0 else { continue }
            guard let key = OrganizationLogoCatalog.resolvedKey(
                organization: entry.organization,
                modelName: entry.name
            ) else { continue }
            grouped[key, default: []].append(entry)
        }

        let ordered = grouped.map { key, members in
            aggregate(key: key, members: members)
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            // Best rank, not model count. Count must not promote a company.
            if lhs.bestRank != rhs.bestRank {
                return lhs.bestRank < rhs.bestRank
            }
            return lhs.name < rhs.name
        }

        return ordered.prefix(displayLimit).enumerated().map { index, item in
            CompanyStanding(
                entry: LeaderboardEntry(
                    rank: index + 1,
                    name: item.name,
                    score: item.score,
                    organization: item.name,
                    logoURL: item.logoURL
                ),
                components: item.components
            )
        }
    }

    public static func scoreHelp(for standing: CompanyStanding) -> String {
        let details = standing.components.enumerated().map { index, component in
            let rank = "第\(component.rank)名"
            let score = scoreText(component.score)
            let marker = index == 0 ? " · 最强" : ""
            return "\(component.name) · \(rank) · \(score)\(marker)"
        }
        return ([scoreExplanation] + details).joined(separator: "\n")
    }

    /// Names that still resolve through the logo, purchase, and region catalogs.
    /// Logo key `qwen` is shown as Alibaba because purchase links live under
    /// `alibaba` and the Qwen mark is the logo alias. `microsoftai` must stay
    /// "Microsoft AI": "Microsoft" is a different purchase key and has no links.
    /// Unknown keys keep the best-ranked model's organization when that string
    /// normalizes to the key. A harness name is never substituted for a
    /// hosted-model override, because that organization does not normalize to
    /// the model company's key.
    private static let canonicalNames: [String: String] = [
        "anthropic": "Anthropic",
        "openai": "OpenAI",
        "qwen": "Alibaba",
        "zai": "Z.ai",
        "spacexai": "xAI",
        "stepfun": "StepFun",
        "kimi": "Moonshot",
        "google": "Google",
        "deepseek": "DeepSeek",
        "tencent": "Tencent",
        "meta": "Meta",
        "minimax": "MiniMax",
        "mistral": "Mistral",
        "nvidia": "Nvidia",
        "bytedance": "ByteDance",
        "xiaomi": "Xiaomi",
        "klingai": "KlingAI",
        "krea": "Krea",
        "ideogram": "Ideogram",
        "runway": "Runway",
        "luma": "Luma",
        "blackforestlabs": "Black Forest Labs",
        "fal": "Fal",
        "pixverse": "PixVerse",
        "microsoftai": "Microsoft AI",
        "opencode": "OpenCode",
        "devin": "Devin",
        "reve": "Reve",
        "videorebirth": "Video Rebirth",
        "thinkingmachines": "Thinking Machines",
    ]

    private struct Aggregate {
        var name: String
        var score: Double
        var bestRank: Int
        var logoURL: URL?
        var components: [CompanyStandingComponent]
    }

    private static func aggregate(key: String, members: [LeaderboardEntry]) -> Aggregate {
        let ordered = members.sorted { isStronger($0, than: $1) }
        let flagship = ordered[0]
        let components = ordered.map { member in
            CompanyStandingComponent(
                name: member.name,
                rank: member.rank,
                score: member.score
            )
        }
        return Aggregate(
            name: displayName(key: key, best: flagship),
            score: flagship.score,
            bestRank: flagship.rank,
            logoURL: flagship.logoURL,
            components: components
        )
    }

    /// Highest score is the flagship. Rank, then name, only separate equals.
    private static func isStronger(_ lhs: LeaderboardEntry, than rhs: LeaderboardEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        return lhs.name < rhs.name
    }

    private static func displayName(key: String, best: LeaderboardEntry?) -> String {
        if let canonical = canonicalNames[key] {
            return canonical
        }
        if let organization = best?.organization,
           OrganizationLogoCatalog.normalizedKey(organization) == key {
            return organization
        }
        return key
    }

    private static func scoreText(_ score: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), arguments: [score])
    }
}

public struct CompanyStandingComponent: Equatable, Sendable {
    public let name: String
    public let rank: Int
    public let score: Double

    public init(name: String, rank: Int, score: Double) {
        self.name = name
        self.rank = rank
        self.score = score
    }
}

public struct CompanyStanding: Equatable, Sendable {
    public let entry: LeaderboardEntry
    public let components: [CompanyStandingComponent]

    public init(entry: LeaderboardEntry, components: [CompanyStandingComponent]) {
        self.entry = entry
        self.components = components
    }
}
