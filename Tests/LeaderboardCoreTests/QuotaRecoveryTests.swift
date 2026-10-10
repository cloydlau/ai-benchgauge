import Foundation
import LeaderboardCore
import Testing

struct QuotaRecoveryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func notifiesOnceAfterActualRecoveryIncludingInactiveProviders() {
        var tracker = QuotaRecoveryTracker()
        #expect(tracker.consider(chips: [windows(usage: 20)]).isEmpty)
        #expect(tracker.consider(chips: [windows(usage: 99)]).isEmpty)
        #expect(tracker.consider(chips: [windows(usage: 100)]).isEmpty)
        // Reaching the deadline alone does not generate a recovery.
        #expect(tracker.consider(chips: [windows(usage: 100, reset: now.addingTimeInterval(-1))]).isEmpty)
        let alerts = tracker.consider(chips: [windows(usage: 0, isCurrent: false)])
        #expect(alerts.count == 1)
        #expect(alerts.first?.reason == .recovered)
        #expect(alerts.first?.title == "GLM")
        #expect(alerts.first?.subtitle == "额度已恢复")
        #expect(alerts.first?.body == "5h 100%")
        // Keep an unsuccessful delivery available for retry with the same key.
        #expect(tracker.consider(chips: [windows(usage: 0)]) == alerts)
        tracker.acknowledge(Set(alerts.flatMap(\.componentKeys)))
        #expect(tracker.consider(chips: [windows(usage: 0)]).isEmpty)
        _ = tracker.consider(chips: [windows(usage: 100)])
        let next = tracker.consider(chips: [windows(usage: 0)])
        #expect(next.count == 1)
        #expect(next.first?.componentKeys != alerts.first?.componentKeys)
    }

    @Test
    func anotherProviderCannotClearOrDeliverAnExhaustedProvidersAlert() {
        var tracker = QuotaRecoveryTracker()
        _ = tracker.consider(chips: [windows(usage: 100)])
        let other = AccountQuotaChip(id: "other", shortName: "Other", websiteURL: nil, kind: .zhipu,
            isCurrent: true, status: windows(usage: 0).status)
        #expect(tracker.consider(chips: [other]).isEmpty)
        let alerts = tracker.consider(chips: [other, windows(usage: 0, isCurrent: false)])
        #expect(alerts.map(\.chipID) == ["provider"])
        tracker.acknowledge(["unrelated-key"])
        #expect(tracker.consider(chips: [windows(usage: 0)]) == alerts)
    }

    @Test
    func failuresStaleAndCachedReadingsCannotClearExhaustion() {
        var tracker = QuotaRecoveryTracker()
        _ = tracker.consider(chips: [windows(usage: 100)])
        for status: AccountQuotaChip.Status in [
            .pending, .message(AccountQuotaMessage.queryFailed), .note(text: "未登录", help: ""),
            .windows([]),
            .windows([ParsedQuotaWindow(name: "five_hour", utilization: .nan, resetsAt: nil)]),
            .qwenWebsite(QwenWebsiteQuota(periodLabel: "5h", remainingPercent: 100, resetsAt: nil, isCached: true)),
        ] {
            #expect(tracker.consider(chips: [chip(status: status)]).isEmpty)
        }
        #expect(tracker.consider(chips: [windows(usage: 0, isStale: true)]).isEmpty)
        #expect(tracker.consider(chips: [windows(usage: 0)]).count == 1)
        #expect(tracker.consider(chips: [chip(status: .message(AccountQuotaMessage.network))]).isEmpty)
    }

    @Test
    func waitsUntilAllBlockingWindowsAreUsableAndPresent() {
        var tracker = QuotaRecoveryTracker()
        _ = tracker.consider(chips: [windows(usage: 100, weeklyUsage: 100)])
        #expect(tracker.consider(chips: [windows(usage: 0, weeklyUsage: 100)]).isEmpty)
        // Dropping the still-blocking weekly pool is not recovery.
        #expect(tracker.consider(chips: [windows(usage: 0)]).isEmpty)
        let result = tracker.consider(chips: [windows(usage: 0, weeklyUsage: 70)])
        #expect(result.first?.body == "7d 30%")
    }

    @Test
    func treatsExactZeroAsExhaustionAndIgnoresPlanDatesAndBalances() {
        var tracker = QuotaRecoveryTracker()
        _ = tracker.consider(chips: [windows(usage: 99.9)])
        #expect(tracker.consider(chips: [windows(usage: 0)]).isEmpty)
        _ = tracker.consider(chips: [chip(status: .balances([ParsedBalance(currency: "USD", amount: 0)]))])
        #expect(tracker.consider(chips: [chip(status: .balances([ParsedBalance(currency: "USD", amount: 20)]))]).isEmpty)
        let planDate = ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 100, resetsAt: now)
        _ = tracker.consider(chips: [chip(status: .windows([planDate]))])
        #expect(tracker.consider(chips: [windows(usage: 0)]).isEmpty)
        _ = tracker.consider(chips: [windows(usage: .infinity)])
        #expect(tracker.consider(chips: [windows(usage: 0)]).isEmpty)
    }

    @Test
    func qwenWebsiteAndPlanUseRemainingQuota() {
        var tracker = QuotaRecoveryTracker()
        let empty = QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 0, resetsAt: now)
        let restored = QwenWebsiteQuota(periodLabel: "1mo", remainingPercent: 75, resetsAt: now.addingTimeInterval(86_400))
        _ = tracker.consider(chips: [chip(status: .qwenWebsite(empty))])
        #expect(tracker.consider(chips: [chip(status: .qwenWebsite(restored))]).first?.body == "1mo 75%")
        var planTracker = QuotaRecoveryTracker()
        _ = planTracker.consider(chips: [chip(status: .qwenPlan(QwenPlanQuota(usedPercent: 100, remainingCredits: 0, totalCredits: 100, resetsAt: now)))])
        let plan = QwenPlanQuota(usedPercent: 0, remainingCredits: 100, totalCredits: 100, resetsAt: nil)
        #expect(planTracker.consider(chips: [chip(status: .qwenPlan(plan))]).first?.body == "额度 100%")
    }

    @Test
    func schedulesResetChecksAndThrottlesRetriesWhileInactive() {
        var tracker = QuotaRecoveryTracker()
        let reset = now.addingTimeInterval(3_600)
        _ = tracker.consider(chips: [windows(usage: 100, reset: reset, isCurrent: false)])
        #expect(tracker.refreshDueChipIDs(now: now, lastAttempts: [:]).isEmpty)
        #expect(tracker.refreshDueChipIDs(now: reset, lastAttempts: [:]) == ["provider"])
        #expect(tracker.refreshDueChipIDs(now: reset.addingTimeInterval(299), lastAttempts: ["provider": reset]).isEmpty)
        #expect(tracker.refreshDueChipIDs(now: reset.addingTimeInterval(300), lastAttempts: ["provider": reset]) == ["provider"])
        _ = tracker.consider(chips: [windows(usage: 0)])
        #expect(tracker.refreshDueChipIDs(now: reset, lastAttempts: [:]).isEmpty)
        _ = tracker.consider(chips: [windows(usage: 100)])
        #expect(tracker.refreshDueChipIDs(now: now, lastAttempts: [:]) == ["provider"])
    }

    @Test
    func persistenceSurvivesRestartBeforeAndAfterDelivery() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "QuotaRecoveryTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = QuotaRecoveryStore(fileURL: directory.appending(path: "recovery.json"))
        var tracker = store.load()
        _ = tracker.consider(chips: [windows(usage: 100)])
        try store.save(tracker)
        tracker = store.load()
        let alert = tracker.consider(chips: [windows(usage: 0)])
        #expect(alert.count == 1)
        try store.save(tracker)
        tracker = store.load()
        #expect(tracker.consider(chips: [windows(usage: 0)]) == alert)
        tracker.acknowledge(Set(alert.flatMap(\.componentKeys)))
        try store.save(tracker)
        tracker = store.load()
        #expect(tracker.consider(chips: [windows(usage: 0)]).isEmpty)
    }

    private func windows(usage: Double, reset: Date? = nil, weeklyUsage: Double? = nil,
                         isCurrent: Bool = true, isStale: Bool = false) -> AccountQuotaChip {
        var values = [ParsedQuotaWindow(name: "five_hour", utilization: usage, resetsAt: reset)]
        if let weeklyUsage {
            values.append(ParsedQuotaWindow(name: "weekly_limit", utilization: weeklyUsage, resetsAt: now.addingTimeInterval(86_400)))
        }
        return chip(status: .windows(values), isCurrent: isCurrent, isStale: isStale)
    }

    private func chip(status: AccountQuotaChip.Status, isCurrent: Bool = true, isStale: Bool = false) -> AccountQuotaChip {
        AccountQuotaChip(id: "provider", shortName: "GLM", websiteURL: nil, kind: .zhipu,
                         isCurrent: isCurrent, status: status, isStale: isStale)
    }
}
