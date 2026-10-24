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
        let matches = modelNameMatcher(modelQuery)
        return grouping == .company ? CompanyLeaderboard.rank(entries, summingUsage: board?.kind.isUsage == true).map(\.entry)
            : entries.filter { matches($0.name) }
    }

    public static func modelNameMatches(_ name: String, query: String) -> Bool {
        modelNameMatcher(query)(name)
    }

    /// Prepare the query once per filtering pass, rather than once per row.
    public static func modelNameMatcher(_ query: String) -> (String) -> Bool {
        guard !query.allSatisfy(\.isWhitespace) else { return { _ in true } }
        let locale = Locale(identifier: "en_US_POSIX")
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale) }
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return { name in
            let value = fold(name)
            return words.allSatisfy { value.contains($0) }
        }
    }

    public static func companies(_ board: Leaderboard?, filter: LeaderboardCountryFilter,
                                 openness: LeaderboardOpennessFilter = .all) -> [CompanyStanding] {
        CompanyLeaderboard.rank(filteredEntries(board, country: filter, openness: openness), summingUsage: board?.kind.isUsage == true)
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
        case .usage: language.text("Usage", "用量")
        }
    }

    // Keep these names identical to the desktop's leaderboard column titles.
    public static func title(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: "Artificial Analysis Intelligence Index"
        case .artificialAnalysisCodingAgent: "Artificial Analysis Coding Agent Index"
        case .arenaText: "Arena | Text"
        case .epochECI: "Epoch Capabilities Index"
        case .cloudbaseUsage: "Tencent Cloud | Token share"
        case .vercelUsage: "Vercel AI Gateway | Token share"
        case .openRouterUsage: "OpenRouter | Token usage"
        case .codeArenaWebDev: "Code Arena | WebDev"
        case .artificialAnalysisTextToImage: "Artificial Analysis | 文生图"
        case .arenaTextToImage: "Arena | 文生图"
        case .artificialAnalysisTextToVideo: "Artificial Analysis | 文生视频"
        case .arenaTextToVideo: "Arena | 文生视频"
        }
    }

    /// Concise board names used by the mini-program and desktop table headers.
    public static func columnTitle(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysisCodingAgent: language.text("Artificial Analysis Coding", "Artificial Analysis 编程")
        case .artificialAnalysisTextToImage: language.text("Artificial Analysis Text to Image", "Artificial Analysis 文生图")
        case .arenaTextToImage: language.text("Text to Image Arena", "Arena 文生图")
        case .artificialAnalysisTextToVideo: language == .traditionalChinese ? "Artificial Analysis 文生影片" : language.text("Artificial Analysis Text to Video", "Artificial Analysis 文生视频")
        case .arenaTextToVideo: language == .traditionalChinese ? "Arena 文生影片" : language.text("Text to Video Arena", "Arena 文生视频")
        default: kind.sourceLinkTitle
        }
    }

    public static func explanation(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Task benchmarks", "任务测评")
        case .artificialAnalysisCodingAgent: language.text("Task completion", "任务完成率")
        case .artificialAnalysisTextToImage: language.text("Curated prompts", "场景化盲测")
        case .artificialAnalysisTextToVideo: language.text("Matched settings", "统一设置")
        case .arenaText: language.text("User votes", "用户盲测")
        case .epochECI: language.text("Calibrated tests", "难度校准")
        case .cloudbaseUsage, .vercelUsage: language.text("Token share", "用量占比")
        case .openRouterUsage: language.text("Usage ranking", "用量排行")
        case .codeArenaWebDev: language.text("WebDev votes", "网页开发盲选")
        case .arenaTextToImage, .arenaTextToVideo: language.text("User prompts", "用户出题")
        }
    }

    public static func sourceSummary(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Combines standardized tests across several abilities.", "汇总多项标准化测试，适合看综合能力")
        case .artificialAnalysisCodingAgent: language.text("Scores coding agents on software engineering tasks.", "通过软件工程任务，检验编程智能体的完成能力")
        case .cloudbaseUsage: language.text("Cumulative text-token share across sampled Beijing-time days; full dates unavailable.", "北京时间抽样统计日的文本 token 累计占比；未公开完整日期。")
        case .vercelUsage: language.text("Latest complete day · text token share · absolute volumes unavailable.", "最近完整一天的文本 token 用量占比；不提供绝对用量。")
        case .openRouterUsage: language.text("Latest complete UTC day · input + output tokens · 1B = 1 billion tokens.", "最近完整 UTC 日输入与输出 token 用量；1B = 十亿 token。")
        case .epochECI: language.text("Estimates general capability from benchmark results, accounting for difficulty and discrimination.", "结合不同测试的难度与区分度，估计模型的综合能力")
        case .arenaText: language.text("People compare anonymous answers to real prompts.", "真实提问下盲选回答，贴近用户偏好")
        case .codeArenaWebDev: language.text("People pick the better result from paired web builds.", "用户盲选网页成品，侧重实际观感")
        case .artificialAnalysisTextToImage: language.text("Blind votes across a balanced set of image use cases.", "按用途均衡选题，盲选图片质量")
        case .arenaTextToImage: language.text("People vote on images made from their own prompts.", "用户自由出题并盲选，贴近日常审美")
        case .artificialAnalysisTextToVideo: language.text("Blind votes on videos made with comparable settings.", "相同提示词、统一设置下盲选视频质量")
        case .arenaTextToVideo: language.text("People vote on paired videos from real prompts.", "用户自由出题并盲选，贴近日常偏好")
        }
    }

    public static func scoreText(_ score: Double, kind: LeaderboardKind) -> String {
        if kind.isShareUsage {
            return score > 0 && score < 0.01 ? "<0.01%" : String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), score)
        }
        if kind == .openRouterUsage {
            return score > 0 && score < 0.01 ? "<0.01B" : String(format: "%.2fB", locale: Locale(identifier: "en_US_POSIX"), score)
        }
        return String(format: kind == .epochECI ? "%.2f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), score)
    }

    public static func scoreTitle(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        kind.isShareUsage ? language.text("Share", "占比") : kind == .openRouterUsage ? language.text("Tokens", "用量") : language.text("Score", "分数")
    }

    public static func sourceHelp(_ kind: LeaderboardKind, language: AppLanguage, board: Leaderboard?,
                                  includesFetchTime: Bool = true) -> String {
        var parts = [sourceSummary(kind, language: language), language.text("Scores are not directly comparable across lists", "各榜分数不直接互比")]
        if kind == .openRouterUsage {
            parts = [sourceSummary(kind, language: language), language.text("Top 50 public models; excludes private and zero-data-retention traffic. Provider tokenizers differ. Company totals cover listed models only.", "展示公开流量前 50 名，排除私有及零数据留存流量；各供应商分词方式不同。公司用量仅汇总榜内模型。")]
        }
        if kind.sourcePrefix == "Arena" {
            parts.insert(language.text("Formerly LMSYS Chatbot Arena / LMArena", "原 LMSYS Chatbot Arena / LMArena"), at: 1)
        }
        if kind == .vercelUsage { parts = [sourceSummary(kind, language: language), language.text("Daily data uses UTC 00:00 to 00:00 the next day (08:00 to 08:00 the next day in Beijing). Includes input, output, reasoning and cached tokens; only published model buckets are listed. Company shares sum listed models only. Not comparable to OpenRouter absolute totals.", "按 UTC 当天 00:00 至次日 00:00 统计，对应北京时间当天 08:00 至次日 08:00。包含输入、输出、推理及缓存 token，仅列出官方公布的模型；公司占比只汇总榜内模型。与 OpenRouter 绝对用量口径不同。例外的 Other 不作为模型展示。") ] }
        if kind == .cloudbaseUsage { parts = [sourceSummary(kind, language: language), language.text("Input + output tokens including cache hits. Published model families only; Other excluded. Shares retain source rounding; company totals cover listed families. No absolute volumes or open-data license stated.", "输入与输出 token 之和，含缓存命中；按官方模型系列汇总，排除 Other。保留来源舍入，公司仅汇总榜内系列；未公开绝对用量或开放数据许可。") ] }
        if kind == .vercelUsage, let date = board?.sourceUpdatedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            parts.insert(language.text("Statistical day (UTC): ", "统计日期（UTC）：") + formatter.string(from: date), at: 1)
        }
        if kind.isShareUsage {
            parts.append(language.text("Refresh time records when we retrieved this snapshot; it does not indicate a new source update.", "刷新时间仅表示我们取得这份数据的时间，不代表来源数据刚刚更新。"))
        }
        if !kind.isUsage, let note = board?.sourceNote, !note.isEmpty { parts.append(note) }
        var help = parts.joined(separator: language.text(". ", "。"))
        if kind == .epochECI { help += "\n\n" + EpochAttribution.fullText(language: language) }
        if includesFetchTime { help += language.text(". ", "。") + sourceTimeHelp(board, language: language) }
        return help
    }

    /// Statistical coverage dates stay in source help; share-usage headers show
    /// retrieval time. Other sources prefer publication time, then successful fetch.
    public static func sourceTime(_ board: Leaderboard?, language: AppLanguage,
                                  timeZone: TimeZone = .current, includesYear: Bool = true) -> (text: String, isSourceTime: Bool) {
        let parts = sourceTimeParts(board, language: language, timeZone: timeZone, includesYear: includesYear)
        return ("\(parts.value) \(parts.caption)", parts.isSourceTime)
    }

    /// Keep the timestamp and its status separate so a loading indicator can
    /// replace the caption without parsing localized presentation text.
    public static func sourceTimeParts(_ board: Leaderboard?, language: AppLanguage,
                                       timeZone: TimeZone = .current, includesYear: Bool = true)
        -> (value: String, caption: String, isSourceTime: Bool) {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d HH:mm"
        guard board?.kind.isShareUsage != true, let updated = board?.sourceUpdatedAt else {
            let fetched = board.map { formatter.string(from: $0.fetchedAt) } ?? "—"
            return (fetched, language.text("Refreshed", "刷新"), false)
        }
        if ArenaAttribution.applies(board) { formatter.dateFormat = includesYear ? "yyyy-MM-dd" : "M/d"; formatter.timeZone = TimeZone(secondsFromGMT: 0) }
        return (formatter.string(from: updated), language.text("Published", "发布"), true)
    }

    public static func sourceTimeHelp(_ board: Leaderboard?, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        guard board?.kind.isShareUsage != true, let updated = board?.sourceUpdatedAt else {
            let fetched = board.map { formatter.string(from: $0.fetchedAt) } ?? "—"
            return "\(fetched) \(language.text("Refreshed", "刷新"))"
        }
        if ArenaAttribution.applies(board) { formatter.timeStyle = .none; formatter.timeZone = TimeZone(secondsFromGMT: 0) }
        let value = formatter.string(from: updated)
        return "\(value) \(language.text("Published", "发布"))"
    }

    public static func rankingUpdated(_ snapshot: LeaderboardSnapshot, category: LeaderboardCategory,
                                      language: AppLanguage, now: Date = Date()) -> String {
        guard let date = category.boardKinds.compactMap({ kind in
            snapshot.boards[kind].map { $0.sourceUpdatedAt ?? $0.fetchedAt }
        }).min() else {
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
