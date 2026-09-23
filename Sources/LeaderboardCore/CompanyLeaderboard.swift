import Foundation

/// Company standings derived from one board's model rows.
///
/// The score is a reciprocal-rank weighted mean. Weight is `1 / rank` on that
/// board, then normalized inside the company so the weights sum to 1. A sum,
/// a count, reciprocal-rank fusion, or log-sum-exp would all grow with how
/// many of that company's models made the board. An equal mean lets a long
/// tail erase the frontier model: rank 1 at 100 plus rank 20 at 10 would
/// become 55 instead of about 95.7. A weaker extra model can only pull this
/// mean; it never adds a bonus. Model count is not a tie-break.
public enum CompanyLeaderboard {
    /// The table has 20 slots. Extra companies would not be visible.
    private static let displayLimit = 20

    /// Shown on the company score. Count is named so a longer listing is not
    /// read as a higher score.
    public static let scoreExplanation = "名次加权均分，上榜数量不加分"

    public static func rank(_ entries: [LeaderboardEntry]) -> [CompanyStanding] {
        var grouped: [String: [LeaderboardEntry]] = [:]
        for entry in entries {
            // 1/rank is the weight. A non-positive rank is not a board position.
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
        let details = standing.components.map { component in
            let rank = "第\(component.rank)名"
            let weight = percentText(component.weight)
            let score = scoreText(component.score)
            return "\(component.name) · \(rank) · \(weight) · \(score)"
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
        let rawWeights = members.map { 1.0 / Double($0.rank) }
        let weightSum = rawWeights.reduce(0, +)
        let components = zip(members, rawWeights).map { member, raw in
            CompanyStandingComponent(
                name: member.name,
                rank: member.rank,
                score: member.score,
                weight: raw / weightSum
            )
        }.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.name < rhs.name
        }
        let score = weightedMean(components)
        let best = bestMember(members)
        return Aggregate(
            name: displayName(key: key, best: best),
            score: score,
            bestRank: best?.rank ?? Int.max,
            logoURL: best?.logoURL,
            components: components
        )
    }

    /// Normalized `1/rank` weights do not sum to 1 in floating point. Summing
    /// `score * weight` then ranks a longer listing of the same scores above a
    /// shorter one. The mean of a constant is that constant, so count cannot
    /// move it.
    private static func weightedMean(_ components: [CompanyStandingComponent]) -> Double {
        guard let first = components.first else { return 0 }
        if components.allSatisfy({ $0.score == first.score }) {
            return first.score
        }
        return components.reduce(0.0) { partial, component in
            partial + component.score * component.weight
        }
    }

    private static func bestMember(_ members: [LeaderboardEntry]) -> LeaderboardEntry? {
        members.min { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.name < rhs.name
        }
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

    private static func percentText(_ weight: Double) -> String {
        let percent = Int((weight * 100).rounded())
        return "\(percent)%"
    }

    private static func scoreText(_ score: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), arguments: [score])
    }
}

public struct CompanyStandingComponent: Equatable, Sendable {
    public let name: String
    public let rank: Int
    public let score: Double
    /// Share of this company's score. Components of one standing sum to 1.
    public let weight: Double

    public init(name: String, rank: Int, score: Double, weight: Double) {
        self.name = name
        self.rank = rank
        self.score = score
        self.weight = weight
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
