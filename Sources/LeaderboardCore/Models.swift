import Foundation

public enum LeaderboardKind: String, Codable, CaseIterable, Sendable {
    case artificialAnalysis = "artificialAnalysis"
    case artificialAnalysisCodingAgent = "artificialAnalysisCodingAgent"
    case arenaText = "arenaText"
    case codeArenaWebDev = "codeArenaWebDev"
    case artificialAnalysisTextToImage = "artificialAnalysisTextToImage"
    case arenaTextToImage = "arenaTextToImage"
    case artificialAnalysisTextToVideo = "artificialAnalysisTextToVideo"
    case arenaTextToVideo = "arenaTextToVideo"

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
        case .artificialAnalysisCodingAgent:
            "https://artificialanalysis.ai/agents/coding-agents"
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

    public var sourcePrefix: String {
        switch self {
        case .artificialAnalysis,
             .artificialAnalysisCodingAgent,
             .artificialAnalysisTextToImage,
             .artificialAnalysisTextToVideo:
            "Artificial Analysis"
        case .arenaText, .codeArenaWebDev, .arenaTextToImage, .arenaTextToVideo:
            "Arena"
        }
    }

    public var sourceLinkTitle: String {
        switch self {
        case .artificialAnalysis: "Artificial Analysis"
        case .artificialAnalysisCodingAgent: "Artificial Analysis 编程"
        case .arenaText: "Text Arena"
        case .codeArenaWebDev: "Code Arena"
        case .artificialAnalysisTextToImage: "Artificial Analysis 文生图"
        case .arenaTextToImage: "Arena 文生图"
        case .artificialAnalysisTextToVideo: "Artificial Analysis 文生视频"
        case .arenaTextToVideo: "Arena 文生视频"
        }
    }
}

public enum LeaderboardCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case coding
    case image
    case video

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "综合"
        case .coding: "编程"
        case .image: "图片"
        case .video: "视频"
        }
    }

    public var boardKinds: [LeaderboardKind] {
        switch self {
        case .general: [.artificialAnalysis, .arenaText]
        case .coding: [.artificialAnalysisCodingAgent, .codeArenaWebDev]
        case .image: [.artificialAnalysisTextToImage, .arenaTextToImage]
        case .video: [.artificialAnalysisTextToVideo, .arenaTextToVideo]
        }
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

    public init(
        rank: Int,
        name: String,
        score: Double,
        modelID: String? = nil,
        organization: String? = nil,
        logoURL: URL? = nil
    ) {
        self.rank = rank
        self.name = name
        self.score = score
        self.modelID = modelID
        self.organization = organization
        self.logoURL = logoURL
    }
}

public struct Leaderboard: Codable, Equatable, Sendable {
    public let kind: LeaderboardKind
    public let title: String
    public let sourceUpdatedAt: Date?
    public let sourceNote: String?
    public let fetchedAt: Date
    public let entries: [LeaderboardEntry]
    public let organizationLogoURLs: [String: URL]?

    public init(
        kind: LeaderboardKind,
        title: String,
        sourceUpdatedAt: Date? = nil,
        sourceNote: String? = nil,
        fetchedAt: Date = Date(),
        entries: [LeaderboardEntry],
        organizationLogoURLs: [String: URL]? = nil
    ) {
        self.kind = kind
        self.title = title
        self.sourceUpdatedAt = sourceUpdatedAt
        self.sourceNote = sourceNote
        self.fetchedAt = fetchedAt
        self.entries = entries
        self.organizationLogoURLs = organizationLogoURLs
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
