import Foundation
import Testing
@testable import LeaderboardCore

struct QuotaColorScaleTests {
    @Test
    func testEndpointsAndOutOfRangeValues() {
        for dark in [false, true] {
            let empty = QuotaColorScale.color(remainingPercent: 0, dark: dark)
            let full = QuotaColorScale.color(remainingPercent: 100, dark: dark)
            #expect((empty.red) > (empty.green))
            #expect((full.green) > (full.red))
            #expect((QuotaColorScale.color(remainingPercent: -10, dark: dark)) == (empty))
            #expect((QuotaColorScale.color(remainingPercent: 110, dark: dark)) == (full))
            #expect((QuotaColorScale.color(remainingPercent: .nan, dark: dark)) == (empty))
        }
    }

    @Test
    func testColorsChangeContinuouslyAcrossTheWholeRange() {
        for dark in [false, true] {
            var previous = QuotaColorScale.color(remainingPercent: 0, dark: dark)
            for step in 1...1_000 {
                let color = QuotaColorScale.color(remainingPercent: Double(step) / 10, dark: dark)
                #expect((color) != (previous))
                for (channel, last) in zip([color.red, color.green, color.blue], [previous.red, previous.green, previous.blue]) {
                    #expect((0...1).contains(channel))
                    #expect((abs(channel - last)) < (0.003))
                }
                previous = color
            }
        }
    }

    @Test
    func testQuotaLevelUsesTheLowestUsagePoolAndIgnoresDates() {
        let chip = makeChip(.windows([
            ParsedQuotaWindow(name: "five_hour", utilization: 20, resetsAt: nil),
            ParsedQuotaWindow(name: "seven_day", utilization: 85, resetsAt: nil),
            ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 100, resetsAt: Date()),
        ]))
        #expect((AccountQuotaFormatting.lowestRemainingPercent(for: chip)) == (15))
        let percentages = AccountQuotaFormatting.runs(for: chip, now: Date()).compactMap { run -> Double? in
            if case let .remaining(percent) = run.tone { return percent }
            return nil
        }
        #expect((Set(percentages)) == ([80, 15]))
        #expect((percentages.count) == (2))
        #expect((AccountQuotaFormatting.lowestRemainingPercent(for: makeChip(.balances([
            ParsedBalance(currency: "CNY", amount: 10),
        ])))) == nil)
        #expect((AccountQuotaFormatting.lowestRemainingPercent(for: makeChip(.pending))) == nil)
    }

    @Test
    func testPercentageTonesRetainValuesBetweenOldThresholds() {
        for (used, expected) in [(0.0, 100.0), (69.4, 30.6), (69.5, 30.5), (89.4, 10.6), (89.5, 10.5), (100, 0)] {
            guard case let .remaining(percent) = AccountQuotaFormatting.tone(forUtilization: used) else {
                return recordFailure("expected a percentage color")
            }
            #expect(abs((percent) - (expected)) <= 0.0001)
        }
        #expect((AccountQuotaFormatting.tone(forUtilization: .nan)) == (.secondary))
    }

    @Test
    func testQuotaSourcesUseTheirDisplayedRemainingPercentage() {
        let plan = makeChip(.qwenPlan(QwenPlanQuota(usedPercent: 99, remainingCredits: 75, totalCredits: 100, resetsAt: nil)))
        #expect((AccountQuotaFormatting.lowestRemainingPercent(for: plan)) == (75))
        #expect(AccountQuotaFormatting.runs(for: plan, now: Date()).contains { $0.tone == .remaining(75) })
        let website = makeChip(.qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 12.5, resetsAt: nil)))
        #expect((AccountQuotaFormatting.lowestRemainingPercent(for: website)) == (12.5))
        #expect(AccountQuotaFormatting.runs(for: website, now: Date()).contains { $0.tone == .remaining(12.5) })
    }

    @Test
    func testBalanceReferencePointsAndCurrencyNormalization() {
        for (currency, amounts) in [("CNY", [0.0, 10, 30, 100]), ("USD", [0.0, 2, 5, 20])] {
            for (amount, expected) in zip(amounts, [0.0, 25, 50, 100]) {
                #expect((QuotaColorScale.balanceLevel(amount: amount, currency: currency)) == (expected))
            }
        }
        #expect((QuotaColorScale.balanceLevel(amount: 10, currency: " rmb ")) == (25))
        #expect((QuotaColorScale.balanceLevel(amount: 5, currency: "usd")) == (50))
        #expect((QuotaColorScale.balanceLevel(amount: -1, currency: "CNY")) == (0))
        #expect((QuotaColorScale.balanceLevel(amount: 1_000_000, currency: "CNY")) == (100))
        #expect((QuotaColorScale.balanceLevel(amount: .nan, currency: "CNY")) == nil)
        #expect((QuotaColorScale.balanceLevel(amount: .infinity, currency: "USD")) == nil)
        #expect((QuotaColorScale.balanceLevel(amount: 100, currency: "XYZ")) == nil)
        #expect((QuotaColorScale.balanceLevel(amount: 20_000, currency: "KRW")) == (100))
    }

    @Test
    func testBalanceColorsAreContinuousAcrossReferencePoints() throws {
        for dark in [false, true] {
            for (currency, upper) in [("CNY", 100.0), ("USD", 20.0)] {
                var previous = QuotaColorScale.color(remainingPercent: 0, dark: dark)
                for step in 1...1_000 {
                    let level = try #require(QuotaColorScale.balanceLevel(amount: upper * Double(step) / 1_000, currency: currency))
                    let color = QuotaColorScale.color(remainingPercent: level, dark: dark)
                    #expect((color) != (previous))
                    for (channel, last) in zip([color.red, color.green, color.blue], [previous.red, previous.green, previous.blue]) {
                        #expect((abs(channel - last)) < (0.003))
                    }
                    previous = color
                }
            }
        }
    }

    @Test
    func testFundedWalletDeterminesCardColorWithoutTreatingMoneyAsPercentage() {
        let chip = makeChip(.balances([
            ParsedBalance(currency: "CNY", amount: 0),
            ParsedBalance(currency: "USD", amount: 5),
        ]))
        #expect((AccountQuotaFormatting.colorLevel(for: chip)) == (50))
        #expect(!(AccountQuotaFormatting.isExhausted(chip)))
        #expect((AccountQuotaFormatting.lowestRemainingPercent(for: chip)) == nil)
        #expect((AccountQuotaFormatting.colorLevel(for: makeChip(.balances([
            ParsedBalance(currency: "CNY", amount: 100),
            ParsedBalance(currency: "USD", amount: 2),
        ])))) == (100))
        #expect((AccountQuotaFormatting.colorLevel(for: makeChip(.balances([
            ParsedBalance(currency: "CNY", amount: 0),
            ParsedBalance(currency: "USD", amount: 0),
        ])))) == (0))
        #expect((AccountQuotaFormatting.colorLevel(for: makeChip(.balances([
            ParsedBalance(currency: "XYZ", amount: 10),
        ])))) == nil)
    }

    @Test
    func testDisplayedAmountsRetainTheirOwnColorAndCurrency() {
        let chip = makeChip(.balances([
            ParsedBalance(currency: "USD", amount: 0),
            ParsedBalance(currency: "CNY", amount: 12.36),
            ParsedBalance(currency: "USD", amount: 2),
        ]))
        let runs = AccountQuotaFormatting.runs(for: chip, now: Date())
        #expect((runs.map(\.text).joined()) == ("余 ¥12.36 · 余 $2.00"))
        #expect(runs.contains { $0.text == "¥12.36" && $0.tone == .balance(amount: 12.36, currency: "CNY") })
        #expect(runs.contains { $0.text == "$2.00" && $0.tone == .balance(amount: 2, currency: "USD") })
        let empty = AccountQuotaFormatting.runs(for: makeChip(.balances([ParsedBalance(currency: "CNY", amount: 0)])), now: Date())
        #expect((empty) == ([QuotaTextRun(text: AccountQuotaMessage.emptyBalance, tone: .red)]))
    }

    @Test
    func testDeadlineReferencePointsAndContinuousProgression() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (days, level) in [(-1.0, 0.0), (0, 0), (1, 12.5), (2, 25), (7, 50), (14, 100), (30, 100)] {
            #expect(QuotaColorScale.deadlineLevel(until: now.addingTimeInterval(days * 86_400), now: now) == level)
        }
        #expect(QuotaColorScale.deadlineLevel(until: Date(timeIntervalSince1970: .nan), now: now) == nil)
        for dark in [false, true] {
            var previous = QuotaColorScale.color(remainingPercent: 0, dark: dark)
            for minute in 1...(14 * 24 * 60) {
                let level = try #require(QuotaColorScale.deadlineLevel(until: now.addingTimeInterval(Double(minute) * 60), now: now))
                let color = QuotaColorScale.color(remainingPercent: level, dark: dark)
                #expect(color != previous)
                for (channel, last) in zip([color.red, color.green, color.blue], [previous.red, previous.green, previous.blue]) {
                    #expect(abs(channel - last) < 0.001)
                }
                previous = color
            }
        }
    }

    @Test
    func testOnlyBackgroundCombinesQuotaAndDeadlineUrgency() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (remaining, days, expected) in [(90.0, 2.0, 25.0), (10, 14, 10), (0, 14, 0), (90, -1, 0)] {
            let chip = makeChip(.windows([
                ParsedQuotaWindow(name: "five_hour", utilization: 100 - remaining, resetsAt: nil),
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now.addingTimeInterval(days * 86_400)),
            ]))
            let dateLevel = QuotaColorScale.deadlineLevel(until: now.addingTimeInterval(days * 86_400), now: now)!
            #expect(AccountQuotaFormatting.cardColorLevel(for: chip, now: now) == expected)
            let runs = AccountQuotaFormatting.runs(for: chip, now: now)
            #expect(runs.contains { $0.text == "\(Int(remaining))%" && $0.tone == .remaining(remaining) })
            #expect(runs.last?.tone == .deadline(dateLevel))
            #expect(runs.filter { $0.tone == .secondary }.map(\.text) == ["5h ", " · "])
            #expect(AccountQuotaFormatting.isExhausted(chip) == (remaining == 0))
        }
    }

    @Test
    func testDeadlineColorUsesExactlyTheBoundaryShownOnTheCard() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = now.addingTimeInterval(2 * 86_400)
        let later = now.addingTimeInterval(14 * 86_400)
        let statuses: [AccountQuotaChip.Status] = [
            .windows([ParsedQuotaWindow(name: "monthly", utilization: 10, resetsAt: soon),
                      ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: later)]),
            .qwenPlan(QwenPlanQuota(usedPercent: 10, remainingCredits: 90, totalCredits: 100, resetsAt: soon, expiresAt: later)),
            .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 90, resetsAt: soon, expiresAt: later)),
        ]
        for status in statuses {
            let chip = makeChip(status)
            #expect(AccountQuotaFormatting.deadlineColorLevel(for: chip, now: now) == 100)
            #expect(AccountQuotaFormatting.runs(for: chip, now: now).last?.tone == .deadline(100))
        }
        for status: AccountQuotaChip.Status in [
            .windows([ParsedQuotaWindow(name: "monthly", utilization: 10, resetsAt: soon),
                      ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: nil)]),
            .qwenWebsite(QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 90, resetsAt: soon)),
        ] {
            let chip = makeChip(status)
            #expect(AccountQuotaFormatting.deadlineColorLevel(for: chip, now: now) == 25)
            #expect(AccountQuotaFormatting.runs(for: chip, now: now).last?.tone == .deadline(25))
        }
    }

    @Test
    func testMissingDeadlineAndShortResetsDoNotTriggerDateColors() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let shortReset = now.addingTimeInterval(60)
        let statuses: [AccountQuotaChip.Status] = [
            .windows([ParsedQuotaWindow(name: "five_hour", utilization: 10, resetsAt: shortReset),
                      ParsedQuotaWindow(name: "weekly_limit", utilization: 10, resetsAt: shortReset)]),
            .qwenPlan(QwenPlanQuota(usedPercent: 10, remainingCredits: 90, totalCredits: 100, resetsAt: shortReset)),
            .qwenWebsite(QwenWebsiteQuota(periodLabel: "7d", remainingPercent: 90, resetsAt: shortReset)),
            .pending,
            .balances([ParsedBalance(currency: "USD", amount: 20)]),
        ]
        for status in statuses {
            let chip = makeChip(status)
            #expect(AccountQuotaFormatting.deadlineColorLevel(for: chip, now: now) == nil)
            #expect(AccountQuotaFormatting.cardColorLevel(for: chip, now: now) == AccountQuotaFormatting.colorLevel(for: chip))
            #expect(!AccountQuotaFormatting.runs(for: chip, now: now).contains { if case .deadline = $0.tone { return true }; return false })
        }
        let dateOnly = makeChip(.windows([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 100, resetsAt: now)]))
        #expect(AccountQuotaFormatting.cardColorLevel(for: dateOnly, now: now) == 0)
        #expect(!AccountQuotaFormatting.isExhausted(dateOnly))
        #expect(QuotaAlerts.alerts(for: dateOnly, now: now).isEmpty)
        #expect(!AccountQuotaFormatting.help(for: dateOnly, now: now).contains("已到期"))
    }

    @Test
    func testDateColorReferenceIsTranslatedAndOnlyShownWithADate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let chip = makeChip(.windows([ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0, resetsAt: now)]))
        #expect(AccountQuotaFormatting.help(for: chip, now: now).contains(AccountQuotaFormatting.deadlineColorReference))
        #expect(AppLanguage.english.quotaText(AccountQuotaFormatting.deadlineColorReference).hasPrefix("Date colors:"))
        #expect(AppLanguage.traditionalChinese.quotaText(AccountQuotaFormatting.deadlineColorReference).contains("顏色"))
        #expect(!AccountQuotaFormatting.help(for: makeChip(.pending), now: now).contains(AccountQuotaFormatting.deadlineColorReference))
    }

    private func makeChip(_ status: AccountQuotaChip.Status) -> AccountQuotaChip {
        AccountQuotaChip(id: "color-test", shortName: "Test", websiteURL: nil, kind: .qwen, isCurrent: false, status: status)
    }
}
