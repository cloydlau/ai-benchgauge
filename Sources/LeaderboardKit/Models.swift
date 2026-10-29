import Foundation

public enum LeaderboardKind: String, Codable, CaseIterable, Sendable {
    case artificialAnalysis = "artificialAnalysis"
    case valsSWEbench = "valsSWEbench"
    case artificialAnalysisCodingAgent = "artificialAnalysisCodingAgent"
    case arenaText = "arenaText"
    case epochECI = "epochECI"
    case codeArenaWebDev = "codeArenaWebDev"
    case artificialAnalysisTextToImage = "artificialAnalysisTextToImage"
    case arenaTextToImage = "arenaTextToImage"
    case artificialAnalysisTextToVideo = "artificialAnalysisTextToVideo"
    case arenaTextToVideo = "arenaTextToVideo"
    case cloudbaseUsage = "cloudbaseUsage"
    case vercelUsage = "vercelUsage"
    case openRouterUsage = "openRouterUsage"
    case openRouterPrice = "openRouterPrice"

    public var isUsage: Bool { self == .openRouterUsage || isShareUsage }
    public var isShareUsage: Bool { self == .vercelUsage || self == .cloudbaseUsage }
    public var isPrice: Bool { self == .openRouterPrice }
    public var supportsAACost: Bool {
        [.openRouterUsage, .artificialAnalysis, .artificialAnalysisCodingAgent, .valsSWEbench, .artificialAnalysisTextToImage, .artificialAnalysisTextToVideo].contains(self)
    }

    /// Older builds stored these boards under abbreviated raw values.
    fileprivate static let legacyRawValues: [String: LeaderboardKind] = [
        "aaCodingAgent": .artificialAnalysisCodingAgent,
        "aaTextToImage": .artificialAnalysisTextToImage,
        "aaTextToVideo": .artificialAnalysisTextToVideo,
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let kind = Self(persistedRawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown leaderboard kind \(raw)"
            )
        }
        self = kind
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate init?(persistedRawValue: String) {
        if let kind = Self(rawValue: persistedRawValue) ?? Self.legacyRawValues[persistedRawValue] {
            self = kind
        } else {
            return nil
        }
    }

    public var sourceURL: URL {
        let value = switch self {
        case .artificialAnalysis:
            "https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index"
        case .valsSWEbench: "https://www.vals.ai/benchmarks/swebench"
        case .artificialAnalysisCodingAgent:
            "https://artificialanalysis.ai/agents/coding-agents"
        case .cloudbaseUsage: "https://docs.cloudbase.net/ai/announcement/model-token-volume"
        case .vercelUsage: "https://vercel.com/ai-gateway/leaderboards/models"
        case .openRouterUsage: "https://openrouter.ai/rankings"
        case .openRouterPrice: "https://openrouter.ai/models"
        case .epochECI:
            "https://epoch.ai/eci"
        case .arenaText:
            "https://arena.ai/leaderboard/text"
        case .codeArenaWebDev:
            "https://arena.ai/leaderboard/code/webdev"
        case .artificialAnalysisTextToImage:
            "https://artificialanalysis.ai/image/leaderboard/text-to-image"
        case .arenaTextToImage:
            "https://arena.ai/leaderboard/text-to-image"
        case .artificialAnalysisTextToVideo:
            "https://artificialanalysis.ai/video/leaderboard/text-to-video"
        case .arenaTextToVideo:
            "https://arena.ai/leaderboard/text-to-video"
        }
        return URL(string: value)!
    }

    /// The official machine-readable source may differ from its public leaderboard.
    public var dataURL: URL {
        self == .epochECI ? URL(string: "https://epoch.ai/data/eci_scores.csv")! : sourceURL
    }

    public var sourcePrefix: String {
        switch self {
        case .artificialAnalysis,
             .artificialAnalysisCodingAgent,
             .artificialAnalysisTextToImage,
             .artificialAnalysisTextToVideo:
            "Artificial Analysis"
        case .arenaText, .codeArenaWebDev, .arenaTextToImage, .arenaTextToVideo:
            "Arena"
        case .valsSWEbench: "Vals AI"
        case .epochECI: "Epoch AI"
        case .cloudbaseUsage: "Tencent Cloud"
        case .vercelUsage: "Vercel AI Gateway"
        case .openRouterUsage: "OpenRouter"
        case .openRouterPrice: "OpenRouter"
        }
    }

    public var sourceLinkTitle: String {
        switch self {
        case .artificialAnalysis: "Artificial Analysis"
        case .valsSWEbench: "Vals AI · SWE-bench (Archived)"
        case .artificialAnalysisCodingAgent: "Artificial Analysis 编程"
        case .arenaText: "Text Arena"
        case .epochECI: "Epoch ECI"
        case .cloudbaseUsage: "Tencent Cloud"
        case .vercelUsage: "Vercel AI Gateway"
        case .openRouterUsage: "OpenRouter"
        case .openRouterPrice: "OpenRouter"
        case .codeArenaWebDev: "Code Arena"
        case .artificialAnalysisTextToImage: "Artificial Analysis 文生图"
        case .arenaTextToImage: "Arena 文生图"
        case .artificialAnalysisTextToVideo: "Artificial Analysis 文生视频"
        case .arenaTextToVideo: "Arena 文生视频"
        }
    }
}

public enum LeaderboardCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case usage
    case price
    case general
    case coding
    case image
    case video

    public static let allCases: [LeaderboardCategory] = [.usage, .general, .coding, .image, .video]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "综合"
        case .coding: "编程"
        case .image: "图片"
        case .video: "视频"
        case .usage: "用量"
        case .price: "价格"
        }
    }

    /// The archived Vals snapshot remains selectable for historical comparison.
    public var defaultBoardKinds: [LeaderboardKind] {
        self == .coding ? [.artificialAnalysisCodingAgent, .codeArenaWebDev] : boardKinds
    }

    public var boardKinds: [LeaderboardKind] {
        switch self {
        case .general: [.artificialAnalysis, .arenaText, .epochECI]
        case .coding: [.artificialAnalysisCodingAgent, .codeArenaWebDev, .valsSWEbench]
        case .image: [.artificialAnalysisTextToImage, .arenaTextToImage]
        case .video: [.artificialAnalysisTextToVideo, .arenaTextToVideo]
        case .usage: [.openRouterUsage, .vercelUsage, .cloudbaseUsage]
        case .price: [.openRouterPrice]
        }
    }
}

public enum LeaderboardGrouping: String, Codable, CaseIterable, Identifiable, Sendable {
    case model
    case company

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .model: "模型"
        case .company: "公司"
        }
    }
}

/// Shared PNG travels with the snapshot, so offline views and exports use the same mark.
public struct OrganizationBrand: Codable, Equatable, Sendable {
    public let key: String
    public let colorHex: String
    public let pngData: Data?
    public init(key: String, colorHex: String, pngData: Data? = nil) {
        self.key = key; self.colorHex = colorHex; self.pngData = pngData
    }
    public var validPNGData: Data? {
        guard let pngData, pngData.count >= 33, pngData.count <= 16 * 1024,
              pngData.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]),
              pngData[16..<24] == Data([0, 0, 0, 64, 0, 0, 0, 64]) else { return nil }
        return pngData
    }
}

/// Shared developer headquarters metadata survives offline snapshot caching.
public struct OrganizationCountryMetadata: Codable, Equatable, Sendable {
    public let key: String
    public let countryCode: String?
    public let sourceURL: String?
    public init(key: String, countryCode: String?, sourceURL: String? = nil) {
        self.key = key; self.countryCode = countryCode; self.sourceURL = sourceURL
    }
}

public struct LeaderboardRankChange: Codable, Equatable, Sendable {
    public let delta: Int?
    public let isNew: Bool?

    public init(delta: Int? = nil, isNew: Bool? = nil) {
        self.delta = delta; self.isNew = isNew
    }

    public func text(language: AppLanguage) -> String {
        if isNew == true { return language.text("New", "新") }
        guard let delta, delta != 0 else { return "—" }
        return delta > 0 ? "↑\(delta)" : "↓\(delta.magnitude)"
    }
}

public struct LeaderboardEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { rank }
    public let rank: Int
    public let name: String
    public let score: Double
    public let modelID: String?
    public let organization: String?
    public let logoURL: URL?
    public let openness: ModelOpenness?
    public let brand: OrganizationBrand?
    /// Provider mark stays separate when `brand` contains a model-family mark.
    public let organizationBrand: OrganizationBrand?
    public let developerCountry: OrganizationCountryMetadata?
    public let modelMetadata: ModelMetadata?
    public let voteCount: Int?
    /// Exact upstream decimal string; score uses billions of tokens for display.
    public let totalTokens: String?
    public let rankChange: LeaderboardRankChange?
    public let companyRankChange: LeaderboardRankChange?
    /// Source cost in USD: per evaluation task, per image, or per minute of video,
    /// depending on the leaderboard kind.
    public let taskCostUSD: Double?
    /// AA output tokens/s for general models; seconds/task for coding agents.
    public let speed: Double?
    public let outputPriceUSD: Double?
    public let provider: String?

    public init(
        rank: Int,
        name: String,
        score: Double,
        modelID: String? = nil,
        organization: String? = nil,
        logoURL: URL? = nil,
        openness: ModelOpenness? = nil,
        brand: OrganizationBrand? = nil,
        organizationBrand: OrganizationBrand? = nil,
        developerCountry: OrganizationCountryMetadata? = nil,
        modelMetadata: ModelMetadata? = nil,
        voteCount: Int? = nil,
        totalTokens: String? = nil,
        rankChange: LeaderboardRankChange? = nil,
        companyRankChange: LeaderboardRankChange? = nil,
        taskCostUSD: Double? = nil,
        speed: Double? = nil,
        outputPriceUSD: Double? = nil,
        provider: String? = nil
    ) {
        self.rank = rank
        self.name = name
        self.score = score
        self.modelID = modelID
        self.organization = organization
        self.logoURL = logoURL
        self.openness = openness
        self.brand = brand
        self.organizationBrand = organizationBrand
        self.developerCountry = developerCountry
        self.modelMetadata = modelMetadata
        self.voteCount = voteCount
        self.totalTokens = totalTokens
        self.rankChange = rankChange
        self.companyRankChange = companyRankChange
        self.taskCostUSD = taskCostUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.speed = speed.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.outputPriceUSD = outputPriceUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.provider = provider
    }
}

public struct Leaderboard: Codable, Equatable, Sendable {
    public let kind: LeaderboardKind
    public let title: String
    public let sourceUpdatedAt: Date?
    public let sourceNote: String?
    public let fetchedAt: Date
    /// Last acquisition that changed the ranking; absent in legacy snapshots.
    public let contentUpdatedAt: Date?
    public let entries: [LeaderboardEntry]
    public let organizationLogoURLs: [String: URL]?
    public let modelMetadataSource: ModelMetadataSource?

    public func canReplace(_ previous: Leaderboard?) -> Bool {
        guard let previous else { return true }
        guard kind == previous.kind, fetchedAt >= previous.fetchedAt else { return false }
        if ArenaAttribution.applies(self) && !ArenaAttribution.applies(previous) { return true }
        if ArenaAttribution.applies(previous) && !ArenaAttribution.applies(self) { return false }
        if let priorSourceDate = previous.sourceUpdatedAt {
            return sourceUpdatedAt.map { $0 >= priorSourceDate } ?? false
        }
        return true
    }

    public init(
        kind: LeaderboardKind,
        title: String,
        sourceUpdatedAt: Date? = nil,
        sourceNote: String? = nil,
        fetchedAt: Date = Date(),
        contentUpdatedAt: Date? = nil,
        entries: [LeaderboardEntry],
        organizationLogoURLs: [String: URL]? = nil,
        modelMetadataSource: ModelMetadataSource? = nil
    ) {
        self.kind = kind
        self.title = title
        self.sourceUpdatedAt = sourceUpdatedAt
        self.sourceNote = sourceNote
        self.fetchedAt = fetchedAt
        self.contentUpdatedAt = contentUpdatedAt
        self.entries = entries
        self.organizationLogoURLs = organizationLogoURLs
        self.modelMetadataSource = modelMetadataSource
    }
}

public struct LeaderboardSnapshot: Codable, Equatable, Sendable {
    public var boards: [LeaderboardKind: Leaderboard]

    public init(boards: [LeaderboardKind: Leaderboard] = [:]) {
        self.boards = boards
    }

    private enum CodingKeys: String, CodingKey {
        case boards
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decode([String: Leaderboard].self, forKey: .boards)
        var boards: [LeaderboardKind: Leaderboard] = [:]
        for (key, board) in stored {
            // Skip unrecognized keys so one stale entry cannot drop the cache.
            guard let kind = LeaderboardKind(persistedRawValue: key) else { continue }
            boards[kind] = board
        }
        self.boards = boards
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var stored: [String: Leaderboard] = [:]
        for (kind, board) in boards {
            stored[kind.rawValue] = board
        }
        try container.encode(stored, forKey: .boards)
    }
}
