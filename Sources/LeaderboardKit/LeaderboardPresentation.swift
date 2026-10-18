import Foundation

/// Shared presentation rules for Mac, iPhone and iPad leaderboards.
public enum LeaderboardPresentation {
    /// Keep text layout independent of the background's exact source-score ratio.
    public static func scoreFillRatio(_ score: Double, leaderScore: Double?) -> Double {
        guard score.isFinite, score >= 0, let leaderScore, leaderScore.isFinite, leaderScore > 0 else { return 1 }
        return min(1, score / leaderScore)
    }

    /// Each filtered/grouped source supplies its own leading score.
    public static func scoreShareText(_ score: Double, leaderScore: Double?) -> String {
        guard score.isFinite, score >= 0, let leaderScore, leaderScore.isFinite, leaderScore > 0 else { return "" }
        let percent = (score / leaderScore * 100).rounded(.toNearestOrAwayFromZero)
        guard percent < 100 else { return "" }
        return "\(Int(percent))%"
    }

    public static func rows(_ board: Leaderboard?, grouping: LeaderboardGrouping,
                            country: OrganizationCountry? = nil) -> [LeaderboardEntry] {
        rows(board, grouping: grouping, filter: country.map(LeaderboardCountryFilter.country) ?? .all)
    }

    public static func rows(_ board: Leaderboard?, grouping: LeaderboardGrouping,
                            filter: LeaderboardCountryFilter, openness: LeaderboardOpennessFilter = .all,
                            modelQuery: String = "") -> [LeaderboardEntry] {
        let entries = filteredEntries(board, country: filter, openness: openness)
        return grouping == .company ? CompanyLeaderboard.rank(entries).map(\.entry)
            : entries.filter { modelNameMatches($0.name, query: modelQuery) }
    }

    public static func modelNameMatches(_ name: String, query: String) -> Bool {
        guard !query.allSatisfy(\.isWhitespace) else { return true }
        let locale = Locale(identifier: "en_US_POSIX")
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale) }
        let value = fold(name)
        return fold(query).split(whereSeparator: \.isWhitespace).allSatisfy { value.contains($0) }
    }

    public static func companies(_ board: Leaderboard?, filter: LeaderboardCountryFilter,
                                 openness: LeaderboardOpennessFilter = .all) -> [CompanyStanding] {
        CompanyLeaderboard.rank(filteredEntries(board, country: filter, openness: openness))
    }

    private static func filteredEntries(_ board: Leaderboard?, country: LeaderboardCountryFilter,
                                        openness: LeaderboardOpennessFilter) -> [LeaderboardEntry] {
        (board?.entries ?? []).filter { country.matches($0) && openness.matches($0) }
    }

    public static func countries(_ board: Leaderboard?, grouping: LeaderboardGrouping) -> [OrganizationCountry] {
        let available = Set((board?.entries ?? []).compactMap {
            OrganizationRegion.country(for: $0)
        })
        return OrganizationCountry.allCases.filter { available.contains($0) }
    }

    public static func countryFilters(_ board: Leaderboard?) -> [LeaderboardCountryFilter] {
        let countries = (board?.entries ?? []).map { OrganizationRegion.country(for: $0) }
        let available = Set(countries.compactMap { $0 })
        return [.all] + OrganizationCountry.allCases.filter { available.contains($0) }.map(LeaderboardCountryFilter.country)
            + (countries.contains(where: { $0 == nil }) ? [.unknown] : [])
    }

    public static func title(_ category: LeaderboardCategory, language: AppLanguage) -> String {
        switch category {
        case .general: language.text("General", "综合")
        case .coding: language.text("Coding", "编程")
        case .image: language.text("Image", "图片")
        case .video: language.text("Video", "视频")
        }
    }

    // Keep these names identical to the desktop's leaderboard column titles.
    public static func title(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: "Artificial Analysis Intelligence Index"
        case .artificialAnalysisCodingAgent: "Artificial Analysis Coding Agent Index"
        case .arenaText: "Arena | Text"
        case .epochECI: "Epoch Capabilities Index"
        case .codeArenaWebDev: "Code Arena | WebDev"
        case .artificialAnalysisTextToImage: "Artificial Analysis | 文生图"
        case .arenaTextToImage: "Arena | 文生图"
        case .artificialAnalysisTextToVideo: "Artificial Analysis | 文生视频"
        case .arenaTextToVideo: "Arena | 文生视频"
        }
    }

    public static func explanation(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Task benchmarks", "任务测评")
        case .artificialAnalysisCodingAgent: language.text("Task completion", "任务完成率")
        case .artificialAnalysisTextToImage: language.text("Curated prompts", "场景化盲测")
        case .artificialAnalysisTextToVideo: language.text("Matched settings", "统一设置")
        case .arenaText: language.text("User votes", "用户盲测")
        case .epochECI: language.text("Calibrated scoring", "难度校准")
        case .codeArenaWebDev: language.text("WebDev votes", "网页开发盲选")
        case .arenaTextToImage, .arenaTextToVideo: language.text("User prompts", "用户出题")
        }
    }

    public static func sourceSummary(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Combines standardized tests across several abilities.", "汇总多项标准化测试，适合看综合能力")
        case .artificialAnalysisCodingAgent: language.text("Scores coding agents on software engineering tasks.", "通过软件工程任务，检验编程智能体的完成能力")
        case .epochECI: language.text("Estimates general capability from benchmark results, accounting for difficulty and discrimination.", "结合不同测试的难度与区分度，估计模型的综合能力")
        case .arenaText: language.text("People compare anonymous answers to real prompts.", "真实提问下盲选回答，贴近用户偏好")
        case .codeArenaWebDev: language.text("People pick the better result from paired web builds.", "用户盲选网页成品，侧重实际观感")
        case .artificialAnalysisTextToImage: language.text("Blind votes across a balanced set of image use cases.", "按用途均衡选题，盲选图片质量")
        case .arenaTextToImage: language.text("People vote on images made from their own prompts.", "用户自由出题并盲选，贴近日常审美")
        case .artificialAnalysisTextToVideo: language.text("Blind votes on videos made with comparable settings.", "相同提示词、统一设置下盲选视频质量")
        case .arenaTextToVideo: language.text("People vote on paired videos from real prompts.", "用户自由出题并盲选，贴近日常偏好")
        }
    }

    public static func sourceHelp(_ kind: LeaderboardKind, language: AppLanguage, board: Leaderboard?,
                                  includesFetchTime: Bool = true) -> String {
        var parts = [sourceSummary(kind, language: language), language.text("Scores are not directly comparable across lists", "各榜分数不直接互比")]
        if let date = board?.sourceUpdatedAt {
            let formatter = DateFormatter()
            formatter.locale = language.locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let label = kind.sourcePrefix == "Arena" ? language.text("Votes through", "投票截至") : language.text("Updated", "更新于")
            parts.append("\(label) \(formatter.string(from: date))")
        }
        if let note = board?.sourceNote, !note.isEmpty { parts.append(note) }
        if includesFetchTime { parts.append(sourceTimeHelp(board, language: language)) }
        return parts.joined(separator: language.text(". ", "。"))
    }

    /// Keep source publication and our successful fetch distinct, including
    /// boards whose source publishes no timestamp. Never substitute one for the other.
    public static func sourceTimes(_ board: Leaderboard?, language: AppLanguage,
                                   timeZone: TimeZone = .current) -> (updated: String, fetched: String) {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d HH:mm"
        let updated = board?.sourceUpdatedAt.map { formatter.string(from: $0) } ?? "—"
        let fetched = board.map { formatter.string(from: $0.fetchedAt) } ?? "—"
        return (language.text("Updated \(updated)", "更新 \(updated)"),
                language.text("Fetched \(fetched)", "抓取 \(fetched)"))
    }

    public static func displayTime(_ board: Leaderboard?, language: AppLanguage,
                                   timeZone: TimeZone = .current) -> String {
        guard let board else { return "—" }
        let date = max(board.sourceUpdatedAt ?? board.fetchedAt, board.fetchedAt)
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    public static func sourceTimeHelp(_ board: Leaderboard?, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let updated = board?.sourceUpdatedAt.map { formatter.string(from: $0) }
            ?? language.text("Not published by the source", "来源未提供")
        let fetched = board.map { formatter.string(from: $0.fetchedAt) }
            ?? language.text("Waiting for first fetch", "等待首次抓取")
        return language.text("Source updated: \(updated)\nFetched: \(fetched)",
                             "源更新时间：\(updated)\n抓取时间：\(fetched)")
    }

    public static func rankingUpdated(_ snapshot: LeaderboardSnapshot, category: LeaderboardCategory,
                                      language: AppLanguage, now: Date = Date()) -> String {
        guard let date = category.boardKinds.compactMap({ snapshot.boards[$0]?.fetchedAt }).min() else {
            return language.text("Rankings pending", "榜单 待更新")
        }
        return language.text("Rankings \(updateAge(date, language: language, now: now))", "榜单 \(updateAge(date, language: language, now: now))")
    }

    public static func updateAge(_ date: Date, language: AppLanguage, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return language.text("just now", "刚刚") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return language.text("\(minutes) min ago", "\(minutes) 分钟前") }
        let hours = Int(seconds / 3600)
        if hours < 24 { return language.text("\(hours) hr ago", "\(hours) 小时前") }
        let days = Int(seconds / 86_400)
        return language.text("\(days) \(days == 1 ? "day" : "days") ago", "\(days) 天前")
    }

    public static func rankLabel(_ rank: Int) -> String {
        switch rank { case 1: "🥇"; case 2: "🥈"; case 3: "🥉"; default: "\(rank)" }
    }
}

public enum LeaderboardCountryFilter: Equatable, Sendable, Hashable {
    case all, country(OrganizationCountry), unknown

    public func matches(_ entry: LeaderboardEntry) -> Bool {
        let country = OrganizationRegion.country(for: entry)
        return switch self { case .all: true; case .country(let selected): country == selected; case .unknown: country == nil }
    }
    public func title(language: AppLanguage) -> String {
        switch self {
        case .all: language.text("All countries", "全部国家")
        case .country(let country): "\(country.flagEmoji)  \(country.localizedName(language: language))"
        case .unknown: language.text("Unknown country", "未知")
        }
    }
}
