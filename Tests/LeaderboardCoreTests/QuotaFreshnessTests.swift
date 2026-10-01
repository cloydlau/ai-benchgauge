import Foundation
import LeaderboardCore
import Testing

struct QuotaFreshnessTests {
    @Test func successfulValuesAdvanceTheDataTimeButFailureAndStateReadsDoNot() {
        let old = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        func chip(_ status: AccountQuotaChip.Status, stale: Bool = false) -> AccountQuotaChip {
            AccountQuotaChip(id: "fixture", shortName: "Fixture", websiteURL: nil, kind: .kimi,
                             isCurrent: true, status: status, isStale: stale)
        }
        let values = AccountQuotaChip.Status.windows([ParsedQuotaWindow(name: "week", utilization: 25, resetsAt: nil)])
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(values)], previous: old, now: now) == now)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(values, stale: true)], previous: old, now: now) == old)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.message(AccountQuotaMessage.network))], previous: old, now: now) == old)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.pending)], previous: nil, now: now) == nil)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.windows([]))], previous: old, now: now) == old)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [], previous: old, now: now) == old)
        let cached = QwenWebsiteQuota(periodLabel: "month", remainingPercent: 75, resetsAt: nil,
                                     expiresAt: nil, isCached: true, capturedAt: old)
        #expect(QuotaFreshness.updatedAt(afterRefreshing: [chip(.qwenWebsite(cached))], previous: nil, now: now) == old)
    }
}
