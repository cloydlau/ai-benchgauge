import Foundation
import LeaderboardCore
import Testing

struct QuotaAlertsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func testIgnoresProvidersThatAreNotCurrent() {
        let chip = chip(
            isCurrent: false,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval(86_400)),
            ])
        )
        #expect(QuotaAlerts.alerts(for: chip, now: now).isEmpty)
    }

    @Test
    func testLowRemainingUsesRemainingNotUtilization() {
        let nearlyEmpty = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 96, resetsAt: nil),
        ])
        #expect((nearlyEmpty.map(\.reason)) == ([.lowRemaining]))
        #expect((nearlyEmpty[0].title) == ("Qwen"))
        #expect((nearlyEmpty[0].subtitle) == ("余量不足10%"))
        #expect((nearlyEmpty[0].body) == ("5h 4%"))

        let above = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 89, resetsAt: nil),
        ])
        #expect(above.isEmpty)
    }

    @Test
    func testRoundsRemainingTheSameWayAsTheChip() {
        #expect((alerts(windows: [ParsedQuotaWindow(name: "five_hour", utilization: 89.6, resetsAt: nil)]).map(\.reason)) == ([.lowRemaining]))
        #expect(alerts(windows: [ParsedQuotaWindow(name: "five_hour", utilization: 89.4, resetsAt: nil)]).isEmpty)
        #expect((alerts(windows: [ParsedQuotaWindow(name: "five_hour", utilization: 90, resetsAt: nil)])[0].body) == ("5h 10%"))
    }

    @Test
    func testSkipsNonFiniteUtilization() {
        #expect(alerts(windows: [
                ParsedQuotaWindow(name: "five_hour", utilization: .nan, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: .infinity, resetsAt: nil),
            ]).isEmpty)
    }

    @Test
    func testMentionsOnlyWindowsThatReachTheThresholdInChipOrder() {
        let later = now.addingTimeInterval(8 * 86_400)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 99, resetsAt: later),
            ParsedQuotaWindow(name: "five_hour", utilization: 40, resetsAt: nil),
        ])
        #expect((result.map(\.reason)) == ([.lowRemaining]))
        #expect((result[0].body) == ("7d 1%"))
        #expect((result[0].componentKeys.count) == (1))
    }

    @Test
    func testLowRemainingMentionsTheLaterExpiryFirst() {
        let soon = now.addingTimeInterval(3_600)
        let later = now.addingTimeInterval(8 * 86_400)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 99, resetsAt: soon),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 98, resetsAt: later),
        ])
        #expect((result.map(\.reason)) == ([.lowRemaining]))
        #expect((result[0].body) == ("7d 2%；5h 1%"))
    }

    @Test
    func testLowRemainingKeyIgnoresPercentAndChangesWithReset() {
        let reset = now.addingTimeInterval(8 * 86_400)
        let emptier = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 99, resetsAt: reset),
        ])
        let fuller = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 96, resetsAt: reset),
        ])
        #expect((emptier[0].componentKeys) == (fuller[0].componentKeys))

        let nextCycle = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 99, resetsAt: reset.addingTimeInterval(86_400)),
        ])
        #expect((emptier[0].componentKeys) != (nextCycle[0].componentKeys))
    }

    @Test
    func testShortWindowsAreNotTreatedAsExpiring() {
        let soon = now.addingTimeInterval(3 * 3_600)
        let fiveHour = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 40, resetsAt: soon),
        ])
        #expect(fiveHour.isEmpty)

        let twoDay = alerts(windows: [
            ParsedQuotaWindow(name: "2_day", utilization: 40, resetsAt: soon),
        ])
        #expect(twoDay.isEmpty)

        let threeDay = alerts(windows: [
            ParsedQuotaWindow(name: "3_day", utilization: 40, resetsAt: soon),
        ])
        #expect((threeDay.map(\.reason)) == ([.expiring]))
    }

    @Test
    func testExpiringBoundaryIsTwoDaysAndNotAlreadyPast() {
        let weekly = { (interval: TimeInterval) in
            self.alerts(windows: [
                ParsedQuotaWindow(
                    name: "weekly_limit",
                    utilization: 40,
                    resetsAt: self.now.addingTimeInterval(interval)
                ),
            ])
        }
        let exactly = weekly(QuotaAlerts.expiringInterval)
        #expect((exactly.map(\.reason)) == ([.expiring]))
        #expect((exactly[0].subtitle) == ("本期将在2天内结束"))
        #expect(exactly[0].body.hasPrefix("7d额度 2天后重置，"))

        #expect(weekly(QuotaAlerts.expiringInterval + 1).isEmpty)
        #expect(weekly(0).isEmpty)
        #expect(weekly(-60).isEmpty)
        #expect(alerts(windows: [
                ParsedQuotaWindow(name: "weekly_limit", utilization: 0, resetsAt: nil),
            ]).filter { $0.reason == .expiring }.isEmpty)
    }

    @Test
    func testBothConditionsSendIndependentAlerts() {
        let resetsAt = now.addingTimeInterval(36 * 3_600)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 95, resetsAt: resetsAt),
        ])
        #expect((result.map(\.reason)) == ([.lowRemaining, .expiring]))
        #expect((result[0].body) == ("7d 5%"))
        let phrase = AccountQuotaFormatting.chineseCountdown(until: resetsAt, now: now)
        let date = AccountQuotaFormatting.resetDateText(resetsAt, now: now)
        #expect((result[1].body) == ("7d额度 \(phrase!)后重置，\(date!)"))
        #expect((result[0].componentKeys) != (result[1].componentKeys))
    }

    @Test
    func testLastMinuteUsesAReadablePhrase() {
        let resetsAt = now.addingTimeInterval(30)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 80, resetsAt: resetsAt),
        ])
        #expect((result.map(\.reason)) == ([.expiring]))
        #expect(result[0].body.contains("不到1分钟后重置"))
    }

    @Test
    func testQwenPlanUsesRemainingCreditsRatherThanUsedPercent() {
        let resetsAt = now.addingTimeInterval(10 * 86_400)
        let highCredits = alerts(status: .qwenPlan(QwenPlanQuota(
            usedPercent: 90,
            remainingCredits: 96,
            totalCredits: 100,
            resetsAt: resetsAt
        )))
        #expect(highCredits.isEmpty)

        let lowCredits = alerts(status: .qwenPlan(QwenPlanQuota(
            usedPercent: 0,
            remainingCredits: 10,
            totalCredits: 100,
            resetsAt: resetsAt
        )))
        #expect((lowCredits.map(\.reason)) == ([.lowRemaining]))
        #expect((lowCredits[0].body) == ("额度 10%"))
    }

    @Test
    func testQwenPlanFallsBackWhenCreditsAreMissingAndStillExpires() {
        let resetsAt = now.addingTimeInterval(86_400)
        let result = alerts(status: .qwenPlan(QwenPlanQuota(
            usedPercent: 95,
            remainingCredits: .nan,
            totalCredits: 0,
            resetsAt: nil,
            expiresAt: resetsAt
        )))
        #expect((result.map(\.reason)) == ([.lowRemaining, .expiring]))
        #expect((result[0].body) == ("额度 5%"))
        #expect((result[1].subtitle) == ("本期将在2天内结束"))
        #expect((result[1].body) == (AccountQuotaFormatting.planExpiryPhrase(until: resetsAt, now: now)))
        #expect(!(result[1].body.contains("总到期")))
        #expect(!(result[1].body.contains("后到期")))
        #expect(!(result[1].body.contains("后重置")))
    }

    @Test
    func testQwenWebsiteUsesItsRemainingPercentAndSkipsCache() {
        let resetsAt = now.addingTimeInterval(86_400)
        let fresh = alerts(status: .qwenWebsite(QwenWebsiteQuota(
            periodLabel: "1mo",
            remainingPercent: 4.6,
            resetsAt: resetsAt
        )))
        #expect((fresh.map(\.reason)) == ([.lowRemaining, .expiring]))
        #expect((fresh[0].body) == ("1mo 5%"))

        let cached = alerts(status: .qwenWebsite(QwenWebsiteQuota(
            periodLabel: "1mo",
            remainingPercent: 100,
            resetsAt: resetsAt,
            isCached: true,
            capturedAt: now
        )))
        #expect(cached.isEmpty)
    }

    @Test
    func testBalancesAndFailuresDoNotAlert() {
        #expect(alerts(status: .balances([ParsedBalance(currency: "USD", amount: 20)])).isEmpty)
        #expect(alerts(status: .pending).isEmpty)
        #expect(alerts(status: .message(AccountQuotaMessage.queryFailed)).isEmpty)
        #expect(alerts(status: .note(text: "未登录", help: "help")).isEmpty)
    }

    @Test
    func testRetainedKeysClearOnlyWhenTheCurrentReadingDropsTheCondition() {
        let reset = now.addingTimeInterval(86_400)
        let low = chip(status: .windows([
            ParsedQuotaWindow(name: "weekly_limit", utilization: 99, resetsAt: reset),
        ]))
        let keys = Set(QuotaAlerts.alerts(for: low, now: now).flatMap(\.componentKeys))
        #expect(!(keys.isEmpty))
        #expect((QuotaAlerts.retainedKeys(keys, evaluatedChips: [low], activeKeys: keys)) == (keys))

        let dropped = chip(status: .windows([
            ParsedQuotaWindow(name: "weekly_limit", utilization: 40, resetsAt: now.addingTimeInterval(8 * 86_400)),
        ]))
        #expect(QuotaAlerts.retainedKeys(keys, evaluatedChips: [dropped], activeKeys: []).isEmpty)

        let failed = chip(status: .message(AccountQuotaMessage.queryFailed))
        #expect((QuotaAlerts.retainedKeys(keys, evaluatedChips: [failed], activeKeys: [])) == (keys))

        let cached = chip(status: .qwenWebsite(QwenWebsiteQuota(
            periodLabel: "7d",
            remainingPercent: 1,
            resetsAt: reset,
            isCached: true,
            capturedAt: now
        )))
        #expect((QuotaAlerts.retainedKeys(keys, evaluatedChips: [cached], activeKeys: [])) == (keys))

        let switchedAway = chip(
            isCurrent: false,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 80, resetsAt: reset),
            ])
        )
        #expect((QuotaAlerts.retainedKeys(keys, evaluatedChips: [switchedAway], activeKeys: [])) == (keys))

        let other = chip(
            id: "other",
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 80, resetsAt: reset),
            ])
        )
        #expect((QuotaAlerts.retainedKeys(keys, evaluatedChips: [other], activeKeys: [])) == (keys))
    }

    @Test
    func testChipIDsWithSeparatorsStillMatchTheirOwnKeys() {
        let subject = chip(
            id: "a|b",
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval(86_400)),
            ])
        )
        let keys = Set(QuotaAlerts.alerts(for: subject, now: now).flatMap(\.componentKeys))
        #expect((QuotaAlerts.retainedKeys(keys, evaluatedChips: [subject], activeKeys: keys)) == (keys))
        #expect(!(keys.contains(where: { $0.contains("|") && !$0.contains("a|b") })))
    }

    @Test
    func testPendingAlertsWaitForAnUndeliveredKey() {
        let alert = QuotaAlert(
            chipID: "current",
            reason: .lowRemaining,
            title: "Qwen",
            subtitle: "余量不足10%",
            body: "7d 1%",
            componentKeys: ["k1", "k2"]
        )
        #expect((QuotaAlerts.pendingAlerts([alert], delivered: ["k1"]).map(\.chipID)) == (["current"]))
        #expect(QuotaAlerts.pendingAlerts([alert], delivered: ["k1", "k2"]).isEmpty)
        #expect(QuotaAlerts.pendingAlerts([alert], delivered: ["k2"], inFlight: ["k1"]).isEmpty)
        #expect((QuotaAlerts.pendingAlerts([alert], delivered: [], inFlight: ["k1"]).map(\.chipID)) == (["current"]))
    }

    @Test
    func testZhipuAlertsStayInFiveHourWeeklyPlanOrder() {
        let soon = now.addingTimeInterval(3_600)
        let later = now.addingTimeInterval(6 * 86_400)
        let result = zhipuAlerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 98, resetsAt: later),
            ParsedQuotaWindow(name: "five_hour", utilization: 99, resetsAt: soon),
        ])
        #expect((result.map(\.reason)) == ([.lowRemaining]))
        #expect((result[0].body) == ("5h 1%；7d 2%"))
    }

    @Test
    func testZhipuPlanExpirySkipsRemainingAndDoesNotSayReset() {
        let planEnd = now.addingTimeInterval(36 * 3_600)
        let result = zhipuAlerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 100, resetsAt: now.addingTimeInterval(10 * 86_400)),
            ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: planEnd),
            ParsedQuotaWindow(name: "five_hour", utilization: 0, resetsAt: nil),
        ])
        #expect((result.map(\.reason)) == ([.lowRemaining, .expiring]))
        #expect((result[0].body) == ("7d 0%"))
        #expect(!(result[0].body.contains("总到期")))
        #expect((result[1].subtitle) == ("本期将在2天内结束"))
        #expect(!(result[1].subtitle.contains("重置")))
        #expect((result[1].body) == (AccountQuotaFormatting.planExpiryPhrase(until: planEnd, now: now)))
        #expect(!(result[1].body.contains("总到期")))
        #expect(!(result[1].body.contains("后到期")))
        #expect(!(result[1].body.contains("后重置")))
    }

    @Test
    func testZhipuMixedExpiryKeepsResetSubtitleButUsesExpiryCopyForThePlan() {
        let weeklyReset = now.addingTimeInterval(36 * 3_600)
        let planEnd = now.addingTimeInterval(20 * 3_600)
        let result = zhipuAlerts(windows: [
            ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: planEnd),
            ParsedQuotaWindow(name: "weekly_limit", utilization: 40, resetsAt: weeklyReset),
            ParsedQuotaWindow(name: "five_hour", utilization: 40, resetsAt: now.addingTimeInterval(3_600)),
        ])
        #expect((result.map(\.reason)) == ([.expiring]))
        #expect((result[0].subtitle) == ("本期将在2天内结束"))
        let body = result[0].body
        let expiry = AccountQuotaFormatting.planExpiryPhrase(until: planEnd, now: now)!
        #expect(body.contains("7d额度"))
        #expect(body.contains("后重置"))
        #expect(body.contains(expiry))
        #expect(!(body.contains("总到期")))
        #expect(!(body.contains("后到期")))
        #expect((body.range(of: "7d额度")!.lowerBound) < (body.range(of: expiry)!.lowerBound))
    }

    private func zhipuAlerts(windows: [ParsedQuotaWindow]) -> [QuotaAlert] {
        QuotaAlerts.alerts(
            for: AccountQuotaChip(
                id: "zhipu",
                shortName: "GLM",
                websiteURL: nil,
                kind: .zhipu,
                isCurrent: true,
                status: .windows(windows)
            ),
            now: now
        )
    }

    private func alerts(windows: [ParsedQuotaWindow]) -> [QuotaAlert] {
        alerts(status: .windows(windows))
    }

    private func alerts(status: AccountQuotaChip.Status, isCurrent: Bool = true) -> [QuotaAlert] {
        QuotaAlerts.alerts(for: chip(isCurrent: isCurrent, status: status), now: now)
    }

    private func chip(
        id: String = "current",
        name: String = "Qwen",
        isCurrent: Bool = true,
        status: AccountQuotaChip.Status
    ) -> AccountQuotaChip {
        AccountQuotaChip(
            id: id,
            shortName: name,
            websiteURL: nil,
            kind: .qwen,
            isCurrent: isCurrent,
            status: status
        )
    }
}
