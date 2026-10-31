import Foundation

public enum LeaderboardKind: String, Codable, CaseIterable, Sendable {
    case artificialAnalysis = "artificialAnalysis"
    case valsSWEbench = "valsSWEbench"
    case artificialAnalysisCodingAgent = "artificialAnalysisCodingAgent"
    case arenaText = "arenaText"
    case arenaTextUncontrolled = "arenaTextUncontrolled"
    case epochECI = "epochECI"
    case epochMathECI = "epochMathECI"
    case epochCyberECI = "epochCyberECI"
    case epochSoftwareECI = "epochSoftwareECI"
    case codeArenaWebDev = "codeArenaWebDev"
    case codeArenaImageToWebDev = "codeArenaImageToWebDev"
    case artificialAnalysisTextToImage = "artificialAnalysisTextToImage"
    case artificialAnalysisImageEditing = "artificialAnalysisImageEditing"
    case arenaTextToImage = "arenaTextToImage"
    case arenaImageEditing = "arenaImageEditing"
    case arenaMultiImageEditing = "arenaMultiImageEditing"
    case artificialAnalysisTextToVideo = "artificialAnalysisTextToVideo"
    case artificialAnalysisImageToVideo = "artificialAnalysisImageToVideo"
    case artificialAnalysisVideoEditing = "artificialAnalysisVideoEditing"
    case arenaTextToVideo = "arenaTextToVideo"
    case arenaImageToVideo = "arenaImageToVideo"
    case arenaVideoEditing = "arenaVideoEditing"
    case artificialAnalysisSpeechProviderVoice = "artificialAnalysisSpeechProviderVoice"
    case artificialAnalysisSpeechControlledVoice = "artificialAnalysisSpeechControlledVoice"
    case artificialAnalysisSpeechAgent = "artificialAnalysisSpeechAgent"
    case artificialAnalysisSpeechToText = "artificialAnalysisSpeechToText"
    case artificialAnalysisSpeechToTextStreaming = "artificialAnalysisSpeechToTextStreaming"
    case cloudbaseUsage = "cloudbaseUsage"
    case vercelUsage = "vercelUsage"
    case openRouterUsage = "openRouterUsage"
    case openRouterPrice = "openRouterPrice"

    // Retired kinds remain decodable, but active enumeration includes every
    // selectable variant so shared filters also reach newly added media boards.
    public static var allCases: [LeaderboardKind] {
        LeaderboardCategory.allCases.flatMap(\.boardKinds).flatMap { kind in
            kind.mediaVariants.isEmpty ? [kind] : kind.mediaVariants
        }
    }

    public var isEpoch: Bool { [.epochECI, .epochMathECI, .epochCyberECI, .epochSoftwareECI].contains(self) }
    public var isUsage: Bool { self == .openRouterUsage || isShareUsage }
    public var isShareUsage: Bool { self == .vercelUsage || self == .cloudbaseUsage }
    public var isPrice: Bool { self == .openRouterPrice }
    public var isErrorRate: Bool { self == .artificialAnalysisSpeechToText || self == .artificialAnalysisSpeechToTextStreaming }
    public var isAAImageCost: Bool { self == .artificialAnalysisTextToImage || self == .artificialAnalysisImageEditing }
    public var isAAVideoCost: Bool { [.artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing].contains(self) }
    /// Options belong to one source and one medium; an unavailable counterpart
    /// must not silently substitute a different source's task.
    public var mediaVariants: [LeaderboardKind] {
        switch self {
        case .arenaText, .arenaTextUncontrolled:
            [.arenaText, .arenaTextUncontrolled]
        case .codeArenaWebDev, .codeArenaImageToWebDev:
            [.codeArenaWebDev, .codeArenaImageToWebDev]
        case .artificialAnalysisTextToImage, .artificialAnalysisImageEditing:
            [.artificialAnalysisTextToImage, .artificialAnalysisImageEditing]
        case .arenaTextToImage, .arenaImageEditing, .arenaMultiImageEditing:
            [.arenaTextToImage, .arenaImageEditing, .arenaMultiImageEditing]
        case .artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing:
            [.artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing]
        case .arenaTextToVideo, .arenaImageToVideo, .arenaVideoEditing:
            [.arenaTextToVideo, .arenaImageToVideo, .arenaVideoEditing]
        case .artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice, .artificialAnalysisSpeechAgent, .artificialAnalysisSpeechToText, .artificialAnalysisSpeechToTextStreaming:
            [.artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice, .artificialAnalysisSpeechAgent, .artificialAnalysisSpeechToText, .artificialAnalysisSpeechToTextStreaming]
        default: []
        }
    }

    public func mediaVariantTitle(language: AppLanguage) -> String {
        switch self {
        case .epochECI: language.text("General", "综合")
        case .epochMathECI: language.text("Math", "数学")
        case .epochCyberECI: language.text("Cybersecurity", "网络安全")
        case .arenaText: language.text("Text Style Control", "文本（风格控制）")
        case .arenaTextUncontrolled: language.text("Text Original", "文本（原始总榜）")
        case .codeArenaWebDev: language.text("WebDev", "网页开发")
        case .codeArenaImageToWebDev: language.text("Image to WebDev", "图片转代码")
        case .artificialAnalysisTextToImage, .arenaTextToImage: language.text("Text to image", "文生图")
        case .artificialAnalysisImageEditing: language.text("Image editing", "图片编辑")
        case .arenaImageEditing: language.text("Single-image edit", "单图编辑")
        case .arenaMultiImageEditing: language.text("Multi-image edit", "多图编辑")
        case .artificialAnalysisTextToVideo, .arenaTextToVideo: language.text("Text to video", "文生视频")
        case .artificialAnalysisImageToVideo, .arenaImageToVideo: language.text("Image to video", "图生视频")
        case .artificialAnalysisVideoEditing, .arenaVideoEditing: language.text("Video editing", "视频编辑")
        case .artificialAnalysisSpeechProviderVoice: language.text("TTS · Provider voice", "文字转语音 · 原生声音")
        case .artificialAnalysisSpeechControlledVoice: language.text("TTS · Controlled voice", "文字转语音 · 受控声音")
        case .artificialAnalysisSpeechAgent: language.text("Speech agent", "语音对话")
        case .artificialAnalysisSpeechToText: language.text("STT · Non-streaming", "语音转文字 · 非流式")
        case .artificialAnalysisSpeechToTextStreaming: language.text("STT · Streaming", "语音转文字 · 流式")
        default: ""
        }
    }
    public var supportsAACost: Bool {
        [.openRouterUsage, .artificialAnalysis, .artificialAnalysisCodingAgent, .valsSWEbench, .artificialAnalysisTextToImage, .artificialAnalysisImageEditing, .artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing].contains(self)
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
        case .epochECI, .epochMathECI, .epochCyberECI, .epochSoftwareECI:
            "https://epoch.ai/eci"
        case .arenaText, .arenaTextUncontrolled:
            "https://arena.ai/leaderboard/text"
        case .codeArenaWebDev:
            "https://arena.ai/leaderboard/code/webdev"
        case .codeArenaImageToWebDev:
            "https://arena.ai/leaderboard/code/image-to-webdev"
        case .artificialAnalysisTextToImage:
            "https://artificialanalysis.ai/image/leaderboard/text-to-image"
        case .artificialAnalysisImageEditing: "https://artificialanalysis.ai/image/leaderboard/editing"
        case .arenaTextToImage:
            "https://arena.ai/leaderboard/text-to-image"
        case .arenaImageEditing: "https://arena.ai/leaderboard/image/image-edit/single-image"
        case .arenaMultiImageEditing: "https://arena.ai/leaderboard/image/image-edit/multi-image"
        case .artificialAnalysisTextToVideo:
            "https://artificialanalysis.ai/video/leaderboard/text-to-video"
        case .artificialAnalysisImageToVideo: "https://artificialanalysis.ai/video/leaderboard/image-to-video"
        case .artificialAnalysisVideoEditing: "https://artificialanalysis.ai/video/leaderboard/video-editing"
        case .arenaTextToVideo:
            "https://arena.ai/leaderboard/text-to-video"
        case .arenaImageToVideo: "https://arena.ai/leaderboard/video/image-to-video"
        case .arenaVideoEditing: "https://arena.ai/leaderboard/video/video-edit"
        case .artificialAnalysisSpeechProviderVoice: "https://artificialanalysis.ai/text-to-speech/leaderboard/provider-voice"
        case .artificialAnalysisSpeechControlledVoice: "https://artificialanalysis.ai/text-to-speech/leaderboard/controlled-voice"
        case .artificialAnalysisSpeechAgent: "https://artificialanalysis.ai/speech-to-speech/arena"
        case .artificialAnalysisSpeechToText: "https://artificialanalysis.ai/speech-to-text/non-streaming"
        case .artificialAnalysisSpeechToTextStreaming: "https://artificialanalysis.ai/speech-to-text/streaming"
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
             .artificialAnalysisImageEditing,
             .artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing,
             .artificialAnalysisSpeechProviderVoice, .artificialAnalysisSpeechControlledVoice, .artificialAnalysisSpeechAgent,
             .artificialAnalysisSpeechToText, .artificialAnalysisSpeechToTextStreaming:
            "Artificial Analysis"
        case .arenaText, .arenaTextUncontrolled, .codeArenaWebDev, .codeArenaImageToWebDev, .arenaTextToImage, .arenaImageEditing, .arenaMultiImageEditing, .arenaTextToVideo, .arenaImageToVideo, .arenaVideoEditing:
            "Arena"
        case .valsSWEbench: "Vals AI"
        case .epochECI, .epochMathECI, .epochCyberECI, .epochSoftwareECI: "Epoch AI"
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
        case .arenaText, .arenaTextUncontrolled: "Arena"
        case .epochECI, .epochMathECI, .epochCyberECI, .epochSoftwareECI: "Epoch ECI"
        case .cloudbaseUsage: "Tencent Cloud"
        case .vercelUsage: "Vercel AI Gateway"
        case .openRouterUsage: "OpenRouter"
        case .openRouterPrice: "OpenRouter"
        case .codeArenaWebDev, .codeArenaImageToWebDev: "Arena"
        case .artificialAnalysisTextToImage: "Artificial Analysis 文生图"
        case .artificialAnalysisImageEditing: "Artificial Analysis 图片编辑"
        case .arenaTextToImage: "Arena 文生图"
        case .arenaImageEditing: "Arena 单图编辑"
        case .arenaMultiImageEditing: "Arena 多图编辑"
        case .artificialAnalysisTextToVideo: "Artificial Analysis 文生视频"
        case .artificialAnalysisImageToVideo: "Artificial Analysis 图生视频"
        case .artificialAnalysisVideoEditing: "Artificial Analysis 视频编辑"
        case .arenaTextToVideo: "Arena 文生视频"
        case .arenaImageToVideo: "Arena 图生视频"
        case .arenaVideoEditing: "Arena 视频编辑"
        case .artificialAnalysisSpeechProviderVoice: "Artificial Analysis 文字转语音"
        case .artificialAnalysisSpeechControlledVoice: "Artificial Analysis 受控声音"
        case .artificialAnalysisSpeechAgent: "Artificial Analysis 语音对话"
        case .artificialAnalysisSpeechToText: "Artificial Analysis 语音转文字"
        case .artificialAnalysisSpeechToTextStreaming: "Artificial Analysis 流式语音转文字"
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
    case speech

    public static let allCases: [LeaderboardCategory] = [.usage, .general, .image, .video, .coding, .speech]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "综合"
        case .coding: "编程"
        case .image: "图片"
        case .video: "视频"
        case .speech: "专业"
        case .usage: "用量"
        case .price: "价格"
        }
    }

    public var defaultBoardKinds: [LeaderboardKind] {
        boardKinds
    }

    public var boardKinds: [LeaderboardKind] {
        switch self {
        case .general: [.artificialAnalysis, .arenaText, .epochECI]
        case .coding: [.artificialAnalysisCodingAgent, .codeArenaWebDev, .epochSoftwareECI]
        case .image: [.artificialAnalysisTextToImage, .arenaTextToImage]
        case .video: [.artificialAnalysisTextToVideo, .arenaTextToVideo]
        case .speech: [.artificialAnalysisSpeechProviderVoice, .epochMathECI, .epochCyberECI]
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
