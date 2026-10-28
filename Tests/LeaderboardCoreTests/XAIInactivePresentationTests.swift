import Foundation
import Testing
@testable import LeaderboardCore

struct XAIInactivePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_793_059_200)

    private func chip(state: ParsedSubscriptionState, source: ParsedQuotaDateSource?, end: Date?) -> AccountQuotaChip {
        AccountQuotaChip(id: "xai", shortName: "xAI", websiteURL: nil, kind: .xaiOAuth, isCurrent: true,
            status: .windows([
                ParsedQuotaWindow(name: "weekly_limit", utilization: 0, resetsAt: now.addingTimeInterval(86_400)),
                ParsedQuotaWindow(name: ParsedQuotaWindow.planExpiryName, utilization: 0,
                    resetsAt: end, dateSource: source, subscriptionState: state)
            ]))
    }

    @Test func inactivePlansHideDatesInSummariesHelpAndUrgency() {
        for source in [nil, ParsedQuotaDateSource.cached] {
            for end in [nil, now.addingTimeInterval(-3 * 86_400), now.addingTimeInterval(3 * 86_400)] {
                let value = chip(state: .inactive, source: source, end: end)
                #expect(AccountQuotaFormatting.plainSummary(for: value, now: now) == "未订购")
                #expect(AccountQuotaFormatting.runs(for: value, now: now).count == 1)
                #expect(AccountQuotaFormatting.deadlineColorLevel(for: value, now: now) == nil)
                let help = AccountQuotaFormatting.help(for: value, now: now)
                #expect(help.contains("当前账号没有有效付费套餐"))
                #expect(!help.contains("至"))
                #expect(!help.contains("套餐日期来自已保存"))
                #expect(!help.contains(AccountQuotaFormatting.deadlineColorReference))
                #expect(QuotaAlerts.alerts(for: value, now: now).isEmpty)
            }
        }
    }

    @Test func activeAndUnverifiedPlansStillShowTheirReportedDates() {
        for state in [ParsedSubscriptionState.active, .unverified] {
            let value = chip(state: state, source: .cached, end: now.addingTimeInterval(3 * 86_400))
            let summary = AccountQuotaFormatting.plainSummary(for: value, now: now)
            #expect(summary.contains("至"))
            #expect(!summary.contains("未订购"))
            #expect(AccountQuotaFormatting.deadlineColorLevel(for: value, now: now) != nil)
        }
    }
}
