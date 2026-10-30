import Foundation
#if canImport(SwiftUI)
import SwiftUI

public struct LeaderboardRankChangeBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let change: LeaderboardRankChange?
    let language: AppLanguage
    public init(_ change: LeaderboardRankChange?, language: AppLanguage) {
        self.change = change; self.language = language
    }
    public var body: some View {
        Text(change?.text(language: language) ?? "—")
            .font(.system(size: 8, weight: .semibold)).monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1).minimumScaleFactor(0.65)
    }
    private var tint: Color {
        let dark = colorScheme == .dark
        let rgb: (Double, Double, Double)
        if change?.isNew == true { rgb = dark ? (137, 187, 255) : (50, 118, 202) }
        else if (change?.delta ?? 0) > 0 { rgb = dark ? (255, 146, 146) : (194, 71, 72) }
        else if (change?.delta ?? 0) < 0 { rgb = dark ? (115, 215, 174) : (15, 133, 97) }
        else { return .secondary }
        return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }
}
#endif

/// Shared presentation rules for Mac, iPhone and iPad leaderboards.
public enum LeaderboardPresentation {
    /// Price rank is the current input-price order, independent of cached server ranks.
    public static func priceOrdered(_ entries: [LeaderboardEntry], ascending: Bool = false) -> [LeaderboardEntry] {
        entries.sorted { lhs, rhs in
            if lhs.score != rhs.score { return ascending ? lhs.score < rhs.score : lhs.score > rhs.score }
            let a = lhs.outputPriceUSD ?? 0, b = rhs.outputPriceUSD ?? 0
            if a != b { return ascending ? a < b : a > b }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return (lhs.modelID ?? "") < (rhs.modelID ?? "")
        }.enumerated().map { index, entry in
            LeaderboardEntry(rank: index + 1, name: entry.name, score: entry.score, modelID: entry.modelID,
                organization: entry.organization, logoURL: entry.logoURL, openness: entry.openness,
                brand: entry.brand, organizationBrand: entry.organizationBrand, developerCountry: entry.developerCountry,
                modelMetadata: entry.modelMetadata, voteCount: entry.voteCount, totalTokens: entry.totalTokens,
                taskCostUSD: entry.taskCostUSD, speed: entry.speed, outputPriceUSD: entry.outputPriceUSD, provider: entry.provider)
        }
    }
    public static func supportsAASpeed(_ kind: LeaderboardKind) -> Bool {
        kind == .openRouterUsage || kind == .artificialAnalysis || kind == .artificialAnalysisCodingAgent || kind == .valsSWEbench
    }

    public static func speedPrecedes(_ lhs: LeaderboardEntry, _ rhs: LeaderboardEntry, kind: LeaderboardKind) -> Bool {
        guard let left = lhs.speed else { return rhs.speed == nil && lhs.rank < rhs.rank }
        guard let right = rhs.speed else { return true }
        if left != right { return kind == .artificialAnalysisCodingAgent ? left < right : left > right }
        return lhs.rank < rhs.rank
    }

    public static func speedText(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return String(format: value < 10 ? "%.1f" : "%.0f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
    }
    public static func orderedByTaskCost(_ entries: [LeaderboardEntry], enabled: Bool) -> [LeaderboardEntry] {
        guard enabled else { return entries }
        return entries.sorted(by: taskCostPrecedes)
    }

    public static func taskCostPrecedes(_ lhs: LeaderboardEntry, _ rhs: LeaderboardEntry) -> Bool {
        let left = lhs.taskCostUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? .infinity
        let right = rhs.taskCostUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? .infinity
        if left != right { return left < right }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.rank < rhs.rank
    }

    public static func taskCostText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        if value == 0 { return "$0" }
        if value < 0.001 { return "<$0.001" }
        return String(format: value < 0.01 ? "$%.3f" : "$%.2f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
    }

    public static func taskCostHelp(language: AppLanguage) -> String {
        language.text("Average API cost per task (USD), including applicable cache pricing. Read alongside the benchmark score; this is not cost per successful task or subscription pricing. Company rows show the strongest model's cost. The original ranking and rank changes stay unchanged; missing costs are shown as a dash.",
            "平均每任务 API 成本（美元），包含适用的缓存计费。请结合成绩判断；并非每个成功任务成本或订阅价格。公司行显示最强模型对应的成本。榜单顺序和排名变化保持不变，缺失成本显示为横线。")
    }

    public static func aaCostHelp(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .openRouterUsage:
            language.text("Input/output prices in USD per million tokens; speed is the best available provider's 30-minute p50 throughput. Company values use its most-used listed model. Usage ranking stays unchanged.", "输入/输出价格为每百万 token 美元报价；速度为可用供应商最近 30 分钟最高的 P50 吞吐量。公司值取用量最高的上榜模型；保持原用量排名。")
        case .valsSWEbench:
            language.text("Cost and duration per test as published by Vals; source ranking stays unchanged.", "Vals 公布的每次测试成本和耗时；切换指标不改变原榜排名。")
        case .artificialAnalysisTextToImage:
            language.text("API dollars per image, from AA's price per 1,000 images at 1024×1024 default settings.", "每张图片的 API 美元价格，根据 AA 标注的默认设置、1024×1024 每千张价格换算。")
        case .artificialAnalysisImageEditing:
            language.text("API dollars per edited image, converted from AA's price per 1,000 images; settings can differ by model.", "每张编辑图片的 API 美元价格，根据 AA 每千张价格换算；各模型设置可能不同。")
        case .artificialAnalysisTextToVideo, .artificialAnalysisImageToVideo, .artificialAnalysisVideoEditing:
            language.text("API dollars per minute of generated video; settings and resolution can differ by model.", "生成视频的 API 美元价格，按分钟计；各模型设置和分辨率可能不同。")
        case .artificialAnalysis:
            language.text("Weighted average API cost per Intelligence Index task; calculated using evaluation token usage and prices.", "综合能力评测每任务的加权平均 API 成本，根据评测 token 用量及价格计算。")
        default: taskCostHelp(language: language)
        }
    }

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
        return grouping == .company && board?.kind.isPrice != true ? CompanyLeaderboard.rank(entries, summingUsage: board?.kind.isUsage == true, lowerIsBetter: board?.kind.isErrorRate == true).map(\.entry)
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
        CompanyLeaderboard.rank(filteredEntries(board, country: filter, openness: openness), summingUsage: board?.kind.isUsage == true, lowerIsBetter: board?.kind.isErrorRate == true)
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
        case .speech: language.text("Speech", "语音")
        case .usage: language.text("Usage", "用量")
        case .price: language.text("Price", "价格")
        }
    }

    // Keep these names identical to the desktop's leaderboard column titles.
    public static func title(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: "Artificial Analysis Intelligence Index"
        case .valsSWEbench: "Vals AI · SWE-bench Verified (Archived)"
        case .artificialAnalysisCodingAgent: "Artificial Analysis Coding Agent Index"
        case .arenaText: "Arena | Text · Style Control"
        case .arenaTextUncontrolled: "Arena | Text · Original"
        case .epochECI: "Epoch Capabilities Index"
        case .cloudbaseUsage: "Tencent Cloud | Token share"
        case .vercelUsage: "Vercel AI Gateway | Token share"
        case .openRouterUsage: "OpenRouter | Token usage"
        case .openRouterPrice: "OpenRouter | API prices"
        case .codeArenaWebDev: "Code Arena | WebDev"
        case .codeArenaImageToWebDev: "Code Arena | Image-to-WebDev"
        case .artificialAnalysisTextToImage: "Artificial Analysis | 文生图"
        case .artificialAnalysisImageEditing: language.text("Artificial Analysis | Image editing", "Artificial Analysis | 图片编辑")
        case .arenaTextToImage: "Arena | 文生图"
        case .arenaImageEditing: language.text("Arena | Single-image edit", "Arena | 单图编辑")
        case .arenaMultiImageEditing: language.text("Arena | Multi-image edit", "Arena | 多图编辑")
        case .artificialAnalysisTextToVideo: "Artificial Analysis | 文生视频"
        case .artificialAnalysisImageToVideo: language.text("Artificial Analysis | Image to video", "Artificial Analysis | 图生视频")
        case .artificialAnalysisVideoEditing: language.text("Artificial Analysis | Video editing", "Artificial Analysis | 视频编辑")
        case .arenaTextToVideo: "Arena | 文生视频"
        case .arenaImageToVideo: language.text("Arena | Image to video", "Arena | 图生视频")
        case .arenaVideoEditing: language.text("Arena | Video editing", "Arena | 视频编辑")
        case .artificialAnalysisSpeechProviderVoice: language.text("Artificial Analysis | TTS · Provider voice", "Artificial Analysis | 文字转语音 · 原生声音")
        case .artificialAnalysisSpeechControlledVoice: language.text("Artificial Analysis | TTS · Controlled voice", "Artificial Analysis | 文字转语音 · 受控声音")
        case .artificialAnalysisSpeechAgent: language.text("Artificial Analysis | Speech agent", "Artificial Analysis | 语音对话")
        case .artificialAnalysisSpeechToText: language.text("Artificial Analysis | STT · Non-streaming", "Artificial Analysis | 语音转文字 · 非流式")
        case .artificialAnalysisSpeechToTextStreaming: language.text("Artificial Analysis | STT · Streaming", "Artificial Analysis | 语音转文字 · 流式")
        }
    }

    /// Concise board names used by the mini-program and desktop table headers.
    public static func columnTitle(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysisCodingAgent, .artificialAnalysisTextToImage, .artificialAnalysisTextToVideo: "Artificial Analysis"
        case .arenaTextToImage: language.text("Text to Image Arena", "Arena 文生图")
        case .arenaTextToVideo: language == .traditionalChinese ? "Arena 文生影片" : language.text("Text to Video Arena", "Arena 文生视频")
        default: kind.sourceLinkTitle
        }
    }

    public static func sourceTabTitle(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        explanation(kind, language: language)
    }

    public static func explanation(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Task benchmarks", "任务测评")
        case .valsSWEbench: language.text("Archived benchmark", "已归档榜单")
        case .artificialAnalysisCodingAgent: language.text("Task completion", "任务完成率")
        case .artificialAnalysisTextToImage: language.text("Curated prompts", "场景化盲测")
        case .artificialAnalysisImageEditing: language.text("Image editing", "图片编辑")
        case .artificialAnalysisTextToVideo: language.text("Matched settings", "统一设置")
        case .artificialAnalysisImageToVideo: language.text("Image to video", "图生视频")
        case .artificialAnalysisVideoEditing: language.text("Video editing", "视频编辑")
        case .arenaText, .arenaTextUncontrolled: language.text("User votes", "用户盲测")
        case .epochECI: language.text("Calibrated tests", "难度校准")
        case .cloudbaseUsage: language.text("Cumulative share", "累计占比")
        case .vercelUsage: language.text("Daily share", "每日占比")
        case .openRouterUsage: language.text("Daily usage", "每日用量")
        case .openRouterPrice: language.text("API prices", "API 价格")
        case .codeArenaWebDev: language.text("WebDev votes", "网页开发盲选")
        case .codeArenaImageToWebDev: language.text("Image-to-WebDev votes", "图片转代码盲选")
        case .arenaTextToImage, .arenaTextToVideo: language.text("User prompts", "用户出题")
        case .arenaImageEditing: language.text("Single-image edit", "单图编辑")
        case .arenaMultiImageEditing: language.text("Multi-image edit", "多图编辑")
        case .arenaImageToVideo: language.text("Image to video", "图生视频")
        case .arenaVideoEditing: language.text("Video editing", "视频编辑")
        case .artificialAnalysisSpeechProviderVoice: language.text("Provider voice", "原生声音")
        case .artificialAnalysisSpeechControlledVoice: language.text("Controlled voice", "受控声音")
        case .artificialAnalysisSpeechAgent: language.text("Speech agent", "语音对话")
        case .artificialAnalysisSpeechToText: language.text("Non-streaming STT", "非流式语音转文字")
        case .artificialAnalysisSpeechToTextStreaming: language.text("Streaming STT", "流式语音转文字")
        }
    }

    public static func sourceSummary(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        switch kind {
        case .artificialAnalysis: language.text("Combines standardized tests across several abilities.", "汇总多项标准化测试，适合看综合能力")
        case .valsSWEbench: language.text("Archived SWE-bench Verified: score, cost and duration per test; model and harness variants retain source order. No new models are tested.", "已归档的 SWE-bench Verified：每次测试的分数、成本和耗时；保留模型与代理组合及原榜顺序，不再评测新模型。")
        case .artificialAnalysisCodingAgent: language.text("Coding scores and average API cost per task.", "编程成绩与平均每任务 API 成本")
        case .cloudbaseUsage: language.text("Cumulative text-token share across sampled Beijing-time days; full dates unavailable.", "北京时间抽样统计日的文本 token 累计占比；未公开完整日期。")
        case .vercelUsage: language.text("Latest complete day · text token share · absolute volumes unavailable.", "最近完整一天的文本 token 用量占比；不提供绝对用量。")
        case .openRouterUsage: language.text("Latest complete UTC day · input + output tokens · 1B = 1 billion tokens.", "最近完整 UTC 日输入与输出 token 用量；1B = 十亿 token。")
        case .openRouterPrice: language.text("OpenRouter base text input and output prices per million tokens; context tiers and other charges can differ.", "OpenRouter 文本输入、输出每百万 token 基础价格；长上下文阶梯及其他费用可能不同。")
        case .epochECI: language.text("Estimates general capability from benchmark results, accounting for difficulty and discrimination.", "结合不同测试的难度与区分度，估计模型的综合能力")
        case .arenaText: language.text("Anonymous comparisons with style control.", "真实提问下盲选回答，并进行风格控制")
        case .arenaTextUncontrolled: language.text("Anonymous comparisons without style control.", "真实提问下盲选回答，未进行风格控制")
        case .codeArenaWebDev: language.text("People pick the better result from paired web builds.", "用户盲选网页成品，侧重实际观感")
        case .codeArenaImageToWebDev: language.text("People compare websites generated from images.", "用户盲选由图片生成的网页")
        case .artificialAnalysisTextToImage: language.text("Blind votes across a balanced set of image use cases.", "按用途均衡选题，盲选图片质量")
        case .artificialAnalysisImageEditing: language.text("Blind votes on edited images.", "盲选图片编辑效果")
        case .arenaTextToImage: language.text("People vote on images made from their own prompts.", "用户自由出题并盲选，贴近日常审美")
        case .arenaImageEditing: language.text("People vote on edits to one image.", "用户盲选单图编辑效果")
        case .arenaMultiImageEditing: language.text("People vote on edits using multiple images.", "用户盲选多图编辑效果")
        case .artificialAnalysisTextToVideo: language.text("Blind votes on videos made with comparable settings.", "相同提示词、统一设置下盲选视频质量")
        case .artificialAnalysisImageToVideo: language.text("Blind votes on videos generated from images.", "盲选图片生成视频的效果")
        case .artificialAnalysisVideoEditing: language.text("Blind votes on edited videos.", "盲选视频编辑效果")
        case .arenaTextToVideo: language.text("People vote on paired videos from real prompts.", "用户自由出题并盲选，贴近日常偏好")
        case .arenaImageToVideo: language.text("People vote on videos generated from images.", "用户盲选图片生成的视频")
        case .arenaVideoEditing: language.text("People vote on edited videos.", "用户盲选视频编辑效果")
        case .artificialAnalysisSpeechProviderVoice: language.text("Blind votes on each provider's native voices.", "盲选各供应商的原生声音")
        case .artificialAnalysisSpeechControlledVoice: language.text("Blind votes with controlled voices.", "使用受控声音进行盲选")
        case .artificialAnalysisSpeechAgent: language.text("Blind votes on speech-to-speech agents.", "盲选语音对话代理")
        case .artificialAnalysisSpeechToText: language.text("Speech-to-text word error rate; lower is better.", "语音转文字词错误率，越低越好")
        case .artificialAnalysisSpeechToTextStreaming: language.text("Streaming speech-to-text word error rate; lower is better.", "流式语音转文字词错误率，越低越好")
        }
    }

    public static func scoreText(_ score: Double, kind: LeaderboardKind) -> String {
        if kind.isErrorRate { return String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), score) }
        if kind.isPrice { return taskCostText(score) }
        if kind.isShareUsage {
            return score > 0 && score < 0.01 ? "<0.01%" : String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), score)
        }
        if kind == .openRouterUsage {
            return score > 0 && score < 0.01 ? "<0.01B" : String(format: "%.2fB", locale: Locale(identifier: "en_US_POSIX"), score)
        }
        return String(format: kind == .epochECI ? "%.2f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), score)
    }

    public static func scoreTitle(_ kind: LeaderboardKind, language: AppLanguage) -> String {
        kind.isErrorRate ? "WER ↓" : kind.isPrice ? language.text("In / Out $/1M", "输入/输出 $/百万") : kind.isShareUsage ? language.text("Share", "占比") : kind == .openRouterUsage ? language.text("Tokens", "用量") : language.text("Score", "分数")
    }

    public static func sourceHelp(_ kind: LeaderboardKind, language: AppLanguage, board: Leaderboard?,
                                  includesFetchTime: Bool = true, includesAgreement: Bool = false) -> String {
        var parts = [sourceSummary(kind, language: language), language.text("Scores are not directly comparable across lists", "各榜分数不直接互比")]
        if kind.supportsAACost { parts.append(aaCostHelp(kind, language: language)) }
        if kind == .openRouterUsage {
            parts = [sourceSummary(kind, language: language), language.text("Top 50 public models; excludes private and zero-data-retention traffic. Provider tokenizers differ. Company totals cover listed models only.", "展示公开流量前 50 名，排除私有及零数据留存流量；各供应商分词方式不同。公司用量仅汇总榜内模型。"), aaCostHelp(kind, language: language)]
        }
        if kind.sourcePrefix == "Arena" {
            parts.insert(language.text("Formerly LMSYS Chatbot Arena / LMArena", "原 LMSYS Chatbot Arena / LMArena"), at: 1)
        }
        if kind == .vercelUsage { parts = [sourceSummary(kind, language: language), language.text("Daily data uses UTC 00:00 to 00:00 the next day (08:00 to 08:00 the next day in Beijing). Includes input, output, reasoning and cached tokens; only published model buckets are listed. Company shares sum listed models only. Not comparable to OpenRouter absolute totals.", "按 UTC 当天 00:00 至次日 00:00 统计，对应北京时间当天 08:00 至次日 08:00。包含输入、输出、推理及缓存 token，仅列出官方公布的模型；公司占比只汇总榜内模型。与 OpenRouter 绝对用量口径不同。例外的 Other 不作为模型展示。") ] }
        if kind == .cloudbaseUsage { parts = [sourceSummary(kind, language: language), language.text("Input + output tokens including cache hits. Published model families only; Other excluded. Shares retain source rounding; company totals cover listed families. No absolute volumes or open-data license stated. Refresh time does not indicate a new source update.", "输入与输出 token 之和，含缓存命中；按官方模型系列汇总，排除 Other。保留来源舍入，公司仅汇总榜内系列；未公开绝对用量或开放数据许可。刷新时间不代表来源发布了新数据。") ] }
        if kind == .vercelUsage, let date = board?.sourceUpdatedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            parts.insert(language.text("Statistical day (UTC): ", "统计日期（UTC）：") + formatter.string(from: date), at: 1)
        }
        if kind.isShareUsage {
            parts.append(sourceTimeExplanation(language: language))
        }
        if !kind.isUsage, let note = board?.sourceNote, !note.isEmpty { parts.append(note) }
        var help = parts.joined(separator: language.text(". ", "。"))
        if kind == .epochECI && !includesAgreement { help += "\n\n" + EpochAttribution.fullText(language: language) }
        if includesFetchTime { help += language.text(". ", "。") + sourceTimeHelp(board, language: language) }
        if includesAgreement, let agreement = sourceAgreement(kind, language: language, board: board) {
            help += "\n\n" + agreement
        }
        return help
    }

    /// Complete offline terms for the selected source; never infer a data license.
    public static func sourceAgreement(_ kind: LeaderboardKind, language: AppLanguage, board: Leaderboard?) -> String? {
        switch kind {
        case .openRouterUsage: return CCBYLicense.openRouterText(sourceNote: board?.sourceNote, language: language)
        case .vercelUsage: return CCBYLicense.vercelText(sourceNote: board?.sourceNote, language: language)
        case .cloudbaseUsage: return CloudBaseAttribution.text(sourceNote: board?.sourceNote, language: language)
        case .epochECI: return EpochAttribution.fullText(language: language) + "\n\n" + CCBYLicense.text(language: language)
        default:
            guard board?.kind == kind, ArenaAttribution.applies(board) else { return nil }
            return ArenaAttribution.fullText(language: language) + "\n\n" + CCBYLicense.text(language: language)
        }
    }

    /// Statistical coverage dates stay in source help; share-usage headers show
    /// retrieval time. Other sources prefer publication time, then successful fetch.
    public static func sourceTime(_ board: Leaderboard?, language: AppLanguage,
                                  timeZone: TimeZone = .current, includesYear: Bool = true,
                                  now: Date = Date()) -> (text: String, isSourceTime: Bool) {
        let parts = sourceTimeParts(board, language: language, timeZone: timeZone, includesYear: includesYear, now: now)
        return ("\(parts.value) \(parts.caption)", parts.isSourceTime)
    }

    /// Keep the timestamp and its status separate so a loading indicator can
    /// replace the caption without parsing localized presentation text.
    public static func sourceTimeParts(_ board: Leaderboard?, language: AppLanguage,
                                       timeZone: TimeZone = .current, includesYear: Bool = true, now: Date = Date())
        -> (value: String, caption: String, isSourceTime: Bool) {
        guard board?.kind.isShareUsage != true, let updated = board?.sourceUpdatedAt else {
            let fetched = board.map { calendarTimestamp($0.contentTimestamp, language: language, timeZone: timeZone, now: now) } ?? "—"
            return (fetched, language.text("Refreshed", "刷新"), false)
        }
        let dataset = ArenaAttribution.applies(board)
        let value = calendarTimestamp(updated, language: language,
            timeZone: dataset ? TimeZone(secondsFromGMT: 0)! : timeZone,
            now: now, dateOnly: dataset, includesYear: includesYear)
        return (value, language.text("Published", "发布"), true)
    }

    /// Compare natural days in the displayed timezone, including DST boundaries.
    public static func calendarTimestamp(_ date: Date, language: AppLanguage, timeZone: TimeZone = .current,
                                         now: Date = Date(), dateOnly: Bool = false, includesYear: Bool = false) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        if let days, (0...3).contains(days) {
            let label = language.text(["Today", "Yesterday", "2 days ago", "3 days ago"][days],
                                      ["今天", "昨天", "前天", "大前天"][days])
            if dateOnly { return label }
            formatter.dateFormat = "HH:mm"
            return label + " " + formatter.string(from: date)
        }
        formatter.dateFormat = dateOnly ? (includesYear ? "yyyy-MM-dd" : "M/d") : "M/d HH:mm"
        return formatter.string(from: date)
    }

    public static func sourceTimeExplanationTitle(language: AppLanguage) -> String {
        language.text("Time labels", "时间说明")
    }

    public static func sourceTimeExplanation(language: AppLanguage) -> String {
        language.text(
            "Leaderboard data is updated in real time. There are two types of time labels:\n\nPublished: When a leaderboard provides a publication time, that time is displayed.\n\nRefreshed: When a leaderboard does not provide a publication time, the last time new leaderboard data became available is displayed. Refreshing unchanged data keeps this time unchanged.",
            "榜单数据实时更新。时间标记分为两种：\n\n发布：榜单提供了发布时间，展示其发布时间。\n\n刷新：榜单未提供发布时间，展示上一次更新到新数据的时间；数据没有变化时，时间保持不变。")
    }

    public static func sourceTimeHelp(_ board: Leaderboard?, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        guard board?.kind.isShareUsage != true, let updated = board?.sourceUpdatedAt else {
            let fetched = board.map { formatter.string(from: $0.contentTimestamp) } ?? "—"
            return "\(fetched) \(language.text("Refreshed", "刷新"))"
        }
        if ArenaAttribution.applies(board) { formatter.timeStyle = .none; formatter.timeZone = TimeZone(secondsFromGMT: 0) }
        let value = formatter.string(from: updated)
        return "\(value) \(language.text("Published", "发布"))"
    }

    public static func rankingUpdated(_ snapshot: LeaderboardSnapshot, category: LeaderboardCategory,
                                      language: AppLanguage, now: Date = Date()) -> String {
        let kinds = Set(category.boardKinds.flatMap { [$0] + $0.mediaVariants })
        guard let date = kinds.compactMap({ kind in
            snapshot.boards[kind].map { $0.sourceUpdatedAt ?? $0.contentTimestamp }
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
