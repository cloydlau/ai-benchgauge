import Foundation
import Testing
@testable import LeaderboardCore

struct QuotaDeadlineTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-28T00:00:00Z")!
    private var monthly: Date { now.addingTimeInterval(26 * 86_400) }

    @Test
    func testEveryWindowProviderSeparatesUsageResetsFromSubscriptionEnd() {
        for kind: CCSwitchQuotaKind in [.officialNote, .kimi, .zhipu, .xaiOAuth] {
            let usage = [ParsedQuotaWindow(name: "five_hour", utilization: 20, resetsAt: now.addingTimeInterval(3600)),
                         ParsedQuotaWindow(name: "weekly_limit", utilization: 30, resetsAt: now.addingTimeInterval(7 * 86_400))]
            let withoutPlan = chip(kind, .windows(usage))
            #expect(!(AccountQuotaFormatting.plainSummary(for: withoutPlan, now: now).contains("截至")))
            #expect(AccountQuotaFormatting.help(for: withoutPlan, now: now).contains("7d重置"))
            let withPlan = chip(kind, .windows(usage + [ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: monthly)]))
            #expect(AccountQuotaFormatting.plainSummary(for: withPlan, now: now).contains("至10月24日"))
        }
    }

    @Test
    func testMonthlyBoundaryUsesNeutralCopyAndDoesNotBorrowWeeklyDate() {
        let windows = [ParsedQuotaWindow(name: "weekly_limit", utilization: 10, resetsAt: monthly.addingTimeInterval(86_400)),
                       ParsedQuotaWindow(name: "monthly", utilization: 25, resetsAt: monthly)]
        let summary = AccountQuotaFormatting.plainSummary(for: chip(.kimi, .windows(windows)), now: now)
        #expect(summary.contains("至10月24日"))
        #expect(!(summary.contains("月度重置")))
        #expect(!(summary.contains("10月25日")))
    }

    @Test
    func testKimiCountDurationIdentifiesMonthlyRatherThanFiveHour() {
        let body = Data(#"{"limits":[{"window":{"duration":30,"timeUnit":"TIME_UNIT_DAY"},"detail":{"limit":100,"remaining":75,"resetTime":"2026-10-24T00:00:00Z"}}]}"#.utf8)
        guard case let .windows(windows) = CCSwitchQuotaParsers.parseKimi(body) else { return recordFailure() }
        #expect((windows.map(\.name)) == (["monthly"]))
        #expect((windows.first?.utilization) == (25))
    }

    @Test
    func testKimiUnrecognizedDurationCannotBorrowFiveHourRatio() {
        let body = Data(#"{"limits":[{"window":{"duration":1,"timeUnit":"UNKNOWN"},"detail":{"limit":100,"remaining":50,"resetTime":"2026-10-24T00:00:00Z"}}]}"#.utf8)
        guard case let .windows(windows) = CCSwitchQuotaParsers.parseKimi(body) else { return recordFailure() }
        #expect((windows.map(\.name)) == (["credits"]))
    }

    @Test
    func testZhipuDoesNotGuessPeriodsFromDatesOrUnknownUnits() {
        let body = Data(#"{"success":true,"data":{"limits":[{"type":"tokens_limit","unit":99,"percentage":25,"nextResetTime":1792800000000},{"type":"tokens_limit","percentage":50,"nextResetTime":1790400000000},{"type":"tokens_limit","unit":3,"number":24,"percentage":75}]}}"#.utf8)
        guard case let .windows(windows) = CCSwitchQuotaParsers.parseZhipu(body) else { return recordFailure() }
        #expect((windows.map(\.name)) == (["credits", "credits", "credits"]))
        #expect((windows.map(\.utilization)) == ([25, 50, 75]))
    }

    @Test
    func testQwenMonthlyPercentageAndResetComeFromTheSameSectionInEitherOrder() throws {
        let week = "7天限额 剩余量 80 %\n重置时间 2026-10-05 00:00:00\n"
        let month = "月额度 剩余量 25 %\n重置时间 2026-10-24 00:00:00\n"
        for text in [week + month, month + week] {
            let quota = try #require(QwenWebsiteQuotaParser.parse(Data(text.utf8)))
            #expect((quota.periodLabel) == ("1mo"))
            #expect((quota.remainingPercent) == (25))
            #expect((quota.resetsAt) == (ISO8601DateFormatter().date(from: "2026-10-23T16:00:00Z")))
            #expect((quota.expiresAt) == nil)
            #expect((AccountQuotaFormatting.plainSummary(for: chip(.qwen, .qwenWebsite(quota)), now: now)) == ("1mo 25% · 至10月24日"))
        }
    }

    @Test
    func testQwenMissingMonthlyResetCannotBorrowWeeklyReset() throws {
        let text = "7天限额 剩余量 80 %\n重置时间 2026-10-05 00:00:00\n月额度 剩余量 25 %"
        let quota = try #require(QwenWebsiteQuotaParser.parse(Data(text.utf8)))
        #expect((quota.periodLabel) == ("1mo"))
        #expect((quota.resetsAt) == nil)
    }

    @Test
    func testQwenWebsiteSubscriptionExpiryAndUsageResetRemainDistinctIncludingCacheAndAlerts() throws {
        let text = "套餐有效期至 2026-10-24 00:00:00\n7天限额 剩余量 80 %\n重置时间 2026-10-05 00:00:00"
        let quota = try #require(QwenWebsiteQuotaParser.parse(Data(text.utf8)))
        #expect((quota.expiresAt) != (quota.resetsAt))
        #expect((AccountQuotaFormatting.plainSummary(for: chip(.qwen, .qwenWebsite(quota)), now: now)) == ("7d 80% · 至10月24日"))
        let data = try #require(QwenWebsiteQuotaParser.persistedData(for: quota, capturedAt: now))
        let stored = try #require(QwenWebsiteQuotaParser.parse(data))
        #expect((stored.expiresAt) == (quota.expiresAt))
        #expect((stored.resetsAt) == (quota.resetsAt))
        let alerts = QuotaAlerts.alerts(for: chip(.qwen, .qwenWebsite(quota)), now: quota.expiresAt!.addingTimeInterval(-86_400))
        #expect((alerts.first?.subtitle) == ("本期将在2天内结束"))
        #expect(!(alerts.first?.body.contains("重置") ?? true))
    }

    @Test
    func testLegacyQwenCacheDoesNotReuseAnAmbiguousDate() throws {
        let quota = try #require(QwenWebsiteQuotaParser.parse(Data(#"{"version":1,"periodLabel":"1mo","remainingPercent":25,"resetsAt":811468800,"capturedAt":811296000}"#.utf8)))
        #expect((quota.remainingPercent) == (25))
        #expect((quota.resetsAt) == nil)
        #expect((quota.expiresAt) == nil)
        #expect(quota.isCached)
    }

    @Test
    func testShortResetsDoNotAffectDeadlineSortingAndDeepSeekDoesNotInventDates() {
        let short = chip(.officialNote, .windows([ParsedQuotaWindow(name: "weekly_limit", utilization: 0, resetsAt: now.addingTimeInterval(3600))]))
        let plan = AccountQuotaChip(id: "plan", shortName: "plan", websiteURL: nil, kind: .zhipu, isCurrent: false, status: .windows([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: monthly)]))
        #expect((AccountQuotaFormatting.sortedChips([short, plan]).map(\.id)) == (["plan", "test"]))
        let balance = chip(.deepseek, .balances([ParsedBalance(currency: "CNY", amount: 10)]))
        #expect(!(AccountQuotaFormatting.plainSummary(for: balance, now: now).contains("截至")))
    }

    @Test
    func testCardBoundaryCopyIsNeutralInAllLanguages() {
        #expect((AppLanguage.english.quotaText("至10月24日")) == ("to Oct 24"))
        #expect((AppLanguage.traditionalChinese.quotaText("至10月24日")) == ("至10月24日"))
        #expect((AppLanguage.english.quotaText("本期将在2天内结束")) == ("Current period ends within 2 days"))
    }

    @Test
    func testPassedBoundariesDoNotAssertExpiredAccessOrCanceledRenewal() {
        let past = now.addingTimeInterval(-86_400)
        let cards = [
            chip(.officialNote, .windows([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: past)])),
            chip(.kimi, .windows([ParsedQuotaWindow(name: "monthly", utilization: 25, resetsAt: past)])),
            chip(.qwen, .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 75, resetsAt: past))),
            chip(.qwen, .qwenPlan(QwenPlanQuota(usedPercent: 25, remainingCredits: 75, totalCredits: 100, resetsAt: nil, expiresAt: past))),
        ]
        for card in cards {
            let summary = AccountQuotaFormatting.plainSummary(for: card, now: now)
            #expect(summary.contains("至9月27日"))
            #expect(!(summary.contains("已到期")))
            #expect(!(AccountQuotaFormatting.help(for: card, now: now).contains("已到期")))
            #expect(QuotaAlerts.alerts(for: card, now: now).isEmpty)
        }
    }

    @Test
    func testSubscriptionAndMonthlyUsageBoundariesHaveTheSameCardPhrase() {
        let boundaries = [
            ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: monthly),
            ParsedQuotaWindow(name: "monthly", utilization: 25, resetsAt: monthly),
        ]
        for boundary in boundaries {
            let summary = AccountQuotaFormatting.plainSummary(for: chip(.officialNote, .windows([boundary])), now: now)
            #expect(summary.hasSuffix("至10月24日"))
                #expect(!(summary.contains("月度重置")))
        }
    }

    @Test
    func testQwenCLIRefreshDateIsNotAPlanExpiryOrAnAssumedWeeklyPeriod() throws {
        let body = Data(#"{"token_plan":{"subscribed":true,"totalCredits":100,"remainingCredits":75,"resetDate":"2026-10-24T00:00:00Z"}}"#.utf8)
        let quota = try #require(QwenPlanQuotaParser.parse(body))
        #expect((quota.expiresAt) == nil)
        #expect((quota.resetsAt) == (monthly))
        let card = chip(.qwen, .qwenPlan(quota))
        #expect((AccountQuotaFormatting.plainSummary(for: card, now: now)) == ("额度 75%"))
        #expect((AccountQuotaFormatting.compactMenuBarQuota(for: card)) == ("额度 75%"))
        #expect(AccountQuotaFormatting.help(for: card, now: now).contains("额度重置"))
        let alerts = QuotaAlerts.alerts(for: card, now: monthly.addingTimeInterval(-86_400))
        #expect((alerts.first?.subtitle) == ("本期将在2天内结束"))
        #expect(!(alerts.first?.body.contains("截至") ?? true))
        #expect(!(alerts.first?.body.contains("额度额度") ?? true))
    }

    @Test
    func testQwenCLIOnlyExplicitExpirySuppliesSubscriptionDeadline() throws {
        let body = Data(#"{"token_plan":{"subscribed":true,"totalCredits":100,"remainingCredits":75,"resetDate":"2026-10-05T00:00:00Z","expiresAt":"2026-10-24T00:00:00Z"}}"#.utf8)
        let quota = try #require(QwenPlanQuotaParser.parse(body))
        #expect((quota.resetsAt) != (quota.expiresAt))
        #expect((AccountQuotaFormatting.plainSummary(for: chip(.qwen, .qwenPlan(quota)), now: now)) == ("额度 75% · 至10月24日"))
    }

    @Test
    func testMissingExpiryValueDoesNotMeanThePlanHasExpired() {
        let missing = chip(.officialNote, .windows([ParsedQuotaWindow(name: "five_hour", utilization: 25, resetsAt: nil), ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: nil)]))
        #expect((AccountQuotaFormatting.plainSummary(for: missing, now: now)) == ("5h 75%"))
        #expect(!(AccountQuotaFormatting.help(for: missing, now: now).contains("已到期")))
    }

    private func chip(_ kind: CCSwitchQuotaKind, _ status: AccountQuotaChip.Status) -> AccountQuotaChip {
        AccountQuotaChip(id: "test", shortName: "test", websiteURL: nil, kind: kind, isCurrent: true, status: status)
    }
}
