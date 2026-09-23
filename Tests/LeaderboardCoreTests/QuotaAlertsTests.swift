import Foundation
import LeaderboardCore
import XCTest

final class QuotaAlertsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testIgnoresProvidersThatAreNotCurrent() {
        let chip = chip(
            isCurrent: false,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 0, resetsAt: now.addingTimeInterval(86_400)),
            ])
        )
        XCTAssertTrue(QuotaAlerts.alerts(for: chip, now: now).isEmpty)
    }

    func testHighRemainingUsesRemainingNotUtilization() {
        let full = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 4, resetsAt: nil),
        ])
        XCTAssertEqual(full.map(\.reason), [.highRemaining])
        XCTAssertEqual(full[0].title, "千问")
        XCTAssertEqual(full[0].subtitle, "余量达到95%")
        XCTAssertEqual(full[0].body, "5小时余量 96%")

        let below = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 6, resetsAt: nil),
        ])
        XCTAssertTrue(below.isEmpty)
    }

    func testRoundsRemainingTheSameWayAsTheChip() {
        XCTAssertEqual(
            alerts(windows: [ParsedQuotaWindow(name: "five_hour", utilization: 5.4, resetsAt: nil)]).map(\.reason),
            [.highRemaining]
        )
        XCTAssertTrue(
            alerts(windows: [ParsedQuotaWindow(name: "five_hour", utilization: 5.6, resetsAt: nil)]).isEmpty
        )
        XCTAssertEqual(
            alerts(windows: [ParsedQuotaWindow(name: "five_hour", utilization: 5, resetsAt: nil)])[0].body,
            "5小时余量 95%"
        )
    }

    func testSkipsNonFiniteUtilization() {
        XCTAssertTrue(
            alerts(windows: [
                ParsedQuotaWindow(name: "five_hour", utilization: .nan, resetsAt: nil),
                ParsedQuotaWindow(name: "weekly_limit", utilization: .infinity, resetsAt: nil),
            ]).isEmpty
        )
    }

    func testMentionsOnlyWindowsThatReachTheThresholdInChipOrder() {
        let later = now.addingTimeInterval(8 * 86_400)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: later),
            ParsedQuotaWindow(name: "five_hour", utilization: 40, resetsAt: nil),
        ])
        XCTAssertEqual(result.map(\.reason), [.highRemaining])
        XCTAssertEqual(result[0].body, "7天余量 99%")
        XCTAssertEqual(result[0].componentKeys.count, 1)
    }

    func testHighRemainingKeyIgnoresPercentAndChangesWithReset() {
        let reset = now.addingTimeInterval(8 * 86_400)
        let lowUse = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: reset),
        ])
        let higherUse = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 4, resetsAt: reset),
        ])
        XCTAssertEqual(lowUse[0].componentKeys, higherUse[0].componentKeys)

        let nextCycle = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: reset.addingTimeInterval(86_400)),
        ])
        XCTAssertNotEqual(lowUse[0].componentKeys, nextCycle[0].componentKeys)
    }

    func testShortWindowsAreNotTreatedAsExpiring() {
        let soon = now.addingTimeInterval(3 * 3_600)
        let fiveHour = alerts(windows: [
            ParsedQuotaWindow(name: "five_hour", utilization: 40, resetsAt: soon),
        ])
        XCTAssertTrue(fiveHour.isEmpty)

        let twoDay = alerts(windows: [
            ParsedQuotaWindow(name: "2_day", utilization: 40, resetsAt: soon),
        ])
        XCTAssertTrue(twoDay.isEmpty)

        let threeDay = alerts(windows: [
            ParsedQuotaWindow(name: "3_day", utilization: 40, resetsAt: soon),
        ])
        XCTAssertEqual(threeDay.map(\.reason), [.expiring])
    }

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
        XCTAssertEqual(exactly.map(\.reason), [.expiring])
        XCTAssertEqual(exactly[0].subtitle, "2天内重置")
        XCTAssertTrue(exactly[0].body.hasPrefix("7天额度 2天后重置，"))

        XCTAssertTrue(weekly(QuotaAlerts.expiringInterval + 1).isEmpty)
        XCTAssertTrue(weekly(0).isEmpty)
        XCTAssertTrue(weekly(-60).isEmpty)
        XCTAssertTrue(
            alerts(windows: [
                ParsedQuotaWindow(name: "weekly_limit", utilization: 0, resetsAt: nil),
            ]).filter { $0.reason == .expiring }.isEmpty
        )
    }

    func testBothConditionsSendIndependentAlerts() {
        let resetsAt = now.addingTimeInterval(36 * 3_600)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 2, resetsAt: resetsAt),
        ])
        XCTAssertEqual(result.map(\.reason), [.highRemaining, .expiring])
        XCTAssertEqual(result[0].body, "7天余量 98%")
        let phrase = AccountQuotaFormatting.chineseCountdown(until: resetsAt, now: now)
        let date = AccountQuotaFormatting.resetDateText(resetsAt, now: now)
        XCTAssertEqual(result[1].body, "7天额度 \(phrase!)后重置，\(date!)")
        XCTAssertNotEqual(result[0].componentKeys, result[1].componentKeys)
    }

    func testLastMinuteUsesAReadablePhrase() {
        let resetsAt = now.addingTimeInterval(30)
        let result = alerts(windows: [
            ParsedQuotaWindow(name: "weekly_limit", utilization: 80, resetsAt: resetsAt),
        ])
        XCTAssertEqual(result.map(\.reason), [.expiring])
        XCTAssertTrue(result[0].body.contains("不到1分钟后重置"))
    }

    func testQwenPlanUsesRemainingCreditsRatherThanUsedPercent() {
        let resetsAt = now.addingTimeInterval(10 * 86_400)
        let highCredits = alerts(status: .qwenPlan(QwenPlanQuota(
            usedPercent: 90,
            remainingCredits: 96,
            totalCredits: 100,
            resetsAt: resetsAt
        )))
        XCTAssertEqual(highCredits.map(\.reason), [.highRemaining])
        XCTAssertEqual(highCredits[0].body, "7天余量 96%")

        let lowCredits = alerts(status: .qwenPlan(QwenPlanQuota(
            usedPercent: 0,
            remainingCredits: 10,
            totalCredits: 100,
            resetsAt: resetsAt
        )))
        XCTAssertTrue(lowCredits.isEmpty)
    }

    func testQwenPlanFallsBackWhenCreditsAreMissingAndStillExpires() {
        let resetsAt = now.addingTimeInterval(86_400)
        let result = alerts(status: .qwenPlan(QwenPlanQuota(
            usedPercent: 1,
            remainingCredits: .nan,
            totalCredits: 0,
            resetsAt: resetsAt
        )))
        XCTAssertEqual(result.map(\.reason), [.highRemaining, .expiring])
        XCTAssertEqual(result[0].body, "7天余量 99%")
    }

    func testQwenWebsiteUsesItsRemainingPercentAndSkipsCache() {
        let resetsAt = now.addingTimeInterval(86_400)
        let fresh = alerts(status: .qwenWebsite(QwenWebsiteQuota(
            periodLabel: "1个月",
            remainingPercent: 95.4,
            resetsAt: resetsAt
        )))
        XCTAssertEqual(fresh.map(\.reason), [.highRemaining, .expiring])
        XCTAssertEqual(fresh[0].body, "1个月余量 95%")

        let cached = alerts(status: .qwenWebsite(QwenWebsiteQuota(
            periodLabel: "1个月",
            remainingPercent: 100,
            resetsAt: resetsAt,
            isCached: true,
            capturedAt: now
        )))
        XCTAssertTrue(cached.isEmpty)
    }

    func testBalancesAndFailuresDoNotAlert() {
        XCTAssertTrue(alerts(status: .balances([ParsedBalance(currency: "USD", amount: 20)])).isEmpty)
        XCTAssertTrue(alerts(status: .pending).isEmpty)
        XCTAssertTrue(alerts(status: .message(AccountQuotaMessage.queryFailed)).isEmpty)
        XCTAssertTrue(alerts(status: .note(text: "未登录", help: "help")).isEmpty)
    }

    func testRetainedKeysClearOnlyWhenTheCurrentReadingDropsTheCondition() {
        let reset = now.addingTimeInterval(86_400)
        let high = chip(status: .windows([
            ParsedQuotaWindow(name: "weekly_limit", utilization: 1, resetsAt: reset),
        ]))
        let keys = Set(QuotaAlerts.alerts(for: high, now: now).flatMap(\.componentKeys))
        XCTAssertFalse(keys.isEmpty)
        XCTAssertEqual(
            QuotaAlerts.retainedKeys(keys, evaluatedChips: [high], activeKeys: keys),
            keys
        )

        let dropped = chip(status: .windows([
            ParsedQuotaWindow(name: "weekly_limit", utilization: 40, resetsAt: now.addingTimeInterval(8 * 86_400)),
        ]))
        XCTAssertTrue(QuotaAlerts.retainedKeys(keys, evaluatedChips: [dropped], activeKeys: []).isEmpty)

        let failed = chip(status: .message(AccountQuotaMessage.queryFailed))
        XCTAssertEqual(
            QuotaAlerts.retainedKeys(keys, evaluatedChips: [failed], activeKeys: []),
            keys
        )

        let cached = chip(status: .qwenWebsite(QwenWebsiteQuota(
            periodLabel: "7天",
            remainingPercent: 1,
            resetsAt: reset,
            isCached: true,
            capturedAt: now
        )))
        XCTAssertEqual(
            QuotaAlerts.retainedKeys(keys, evaluatedChips: [cached], activeKeys: []),
            keys
        )

        let switchedAway = chip(
            isCurrent: false,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 80, resetsAt: reset),
            ])
        )
        XCTAssertEqual(
            QuotaAlerts.retainedKeys(keys, evaluatedChips: [switchedAway], activeKeys: []),
            keys
        )

        let other = chip(
            id: "other",
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 80, resetsAt: reset),
            ])
        )
        XCTAssertEqual(
            QuotaAlerts.retainedKeys(keys, evaluatedChips: [other], activeKeys: []),
            keys
        )
    }

    func testChipIDsWithSeparatorsStillMatchTheirOwnKeys() {
        let subject = chip(
            id: "a|b",
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 0, resetsAt: now.addingTimeInterval(86_400)),
            ])
        )
        let keys = Set(QuotaAlerts.alerts(for: subject, now: now).flatMap(\.componentKeys))
        XCTAssertEqual(
            QuotaAlerts.retainedKeys(keys, evaluatedChips: [subject], activeKeys: keys),
            keys
        )
        XCTAssertFalse(keys.contains(where: { $0.contains("|") && !$0.contains("a|b") }))
    }

    func testPendingAlertsWaitForAnUndeliveredKey() {
        let alert = QuotaAlert(
            chipID: "current",
            reason: .highRemaining,
            title: "千问",
            subtitle: "余量达到95%",
            body: "7天余量 99%",
            componentKeys: ["k1", "k2"]
        )
        XCTAssertEqual(QuotaAlerts.pendingAlerts([alert], delivered: ["k1"]).map(\.chipID), ["current"])
        XCTAssertTrue(QuotaAlerts.pendingAlerts([alert], delivered: ["k1", "k2"]).isEmpty)
        XCTAssertTrue(QuotaAlerts.pendingAlerts([alert], delivered: ["k2"], inFlight: ["k1"]).isEmpty)
        XCTAssertEqual(
            QuotaAlerts.pendingAlerts([alert], delivered: [], inFlight: ["k1"]).map(\.chipID),
            ["current"]
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
        name: String = "千问",
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
