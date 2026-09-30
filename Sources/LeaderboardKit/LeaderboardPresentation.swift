import Foundation

public enum LeaderboardPresentation {
    public static func rows(_ board: Leaderboard?, grouping: LeaderboardGrouping,
                            country: OrganizationCountry? = nil) -> [LeaderboardEntry] {
        guard let board else { return [] }
        let rows = grouping == .company ? CompanyLeaderboard.rank(board.entries).map(\.entry) : board.entries
        return rows.filter { row in
            country == nil || OrganizationRegion.country(row.organization, modelName: row.name) == country
        }
    }

    public static func countries(_ board: Leaderboard?, grouping: LeaderboardGrouping) -> [OrganizationCountry] {
        let available = Set(rows(board, grouping: grouping).compactMap {
            OrganizationRegion.country($0.organization, modelName: $0.name)
        })
        return OrganizationCountry.allCases.filter { available.contains($0) }
    }

    public static func title(_ category: LeaderboardCategory, language: AppLanguage) -> String {
        switch category {
        case .general: language.text("General", "综合")
        case .coding: language.text("Coding", "编程")
        case .image: language.text("Image", "图片")
        case .video: language.text("Video", "视频")
        }
    }

    public static func title(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: "Artificial Analysis · Intelligence"
        case .artificialAnalysisCodingAgent: "Artificial Analysis · Coding Agents"
        case .arenaText: "Arena · Text"
        case .codeArenaWebDev: "Code Arena · WebDev"
        case .artificialAnalysisTextToImage: language.text("Artificial Analysis · Text to Image", "Artificial Analysis · 文生图")
        case .arenaTextToImage: language.text("Arena · Text to Image", "Arena · 文生图")
        case .artificialAnalysisTextToVideo: language.text("Artificial Analysis · Text to Video", "Artificial Analysis · 文生视频")
        case .arenaTextToVideo: language.text("Arena · Text to Video", "Arena · 文生视频")
        }
    }

    public static func explanation(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Standardized task benchmarks", "多项标准化任务测评")
        case .artificialAnalysisCodingAgent: language.text("Coding agent task completion", "编程智能体任务完成能力")
        case .artificialAnalysisTextToImage: language.text("Blind votes across curated image use cases", "按用途均衡选题，盲选图片质量")
        case .artificialAnalysisTextToVideo: language.text("Blind votes with matched video settings", "统一设置下盲选视频质量")
        case .arenaText: language.text("Blind user votes on real prompts", "真实提问下的用户盲测")
        case .codeArenaWebDev: language.text("Blind user votes on web builds", "网页成品的用户盲选")
        case .arenaTextToImage: language.text("Blind votes on user image prompts", "用户出题并盲选图片")
        case .arenaTextToVideo: language.text("Blind votes on user video prompts", "用户出题并盲选视频")
        }
    }
}
