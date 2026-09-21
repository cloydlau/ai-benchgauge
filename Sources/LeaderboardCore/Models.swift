import Foundation

public enum LeaderboardKind: String, Codable, CaseIterable, Sendable {
    case artificialAnalysis = "artificialAnalysis"
    case arenaText = "arenaText"
    case codeArenaWebDev = "codeArenaWebDev"
    case aaTextToImage = "aaTextToImage"
    case arenaTextToImage = "arenaTextToImage"
    case aaTextToVideo = "aaTextToVideo"
    case arenaTextToVideo = "arenaTextToVideo"

    public var sourceURL: URL {
        let value = switch self {
        case .artificialAnalysis:
            "https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index"
        case .arenaText:
            "https://arena.ai/leaderboard/text"
        case .codeArenaWebDev:
            "https://arena.ai/leaderboard/code/webdev"
        case .aaTextToImage:
            "https://artificialanalysis.ai/image/leaderboard/text-to-image"
        case .arenaTextToImage:
            "https://arena.ai/leaderboard/text-to-image"
        case .aaTextToVideo:
            "https://artificialanalysis.ai/video/leaderboard/text-to-video"
        case .arenaTextToVideo:
            "https://arena.ai/leaderboard/text-to-video"
        }
        return URL(string: value)!
    }

    public var sourcePrefix: String {
        switch self {
        case .artificialAnalysis, .aaTextToImage, .aaTextToVideo: "AA"
        case .arenaText, .codeArenaWebDev, .arenaTextToImage, .arenaTextToVideo: "Arena"
        }
    }

    public var sourceLinkTitle: String {
        switch self {
        case .artificialAnalysis: "Artificial Analysis"
        case .arenaText: "Text Arena"
        case .codeArenaWebDev: "Code Arena"
        case .aaTextToImage: "AA 文生图"
        case .arenaTextToImage: "Arena 文生图"
        case .aaTextToVideo: "AA 文生视频"
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
        case .coding: [.artificialAnalysis, .codeArenaWebDev]
        case .image: [.aaTextToImage, .arenaTextToImage]
        case .video: [.aaTextToVideo, .arenaTextToVideo]
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
}
