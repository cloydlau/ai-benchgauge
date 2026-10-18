import Foundation
import Testing
@testable import LeaderboardPadUI
import LeaderboardKit

@Suite struct PadAboutContentTests {
    @Test func monthlyInvestmentUsesTheSameRoundingBoundaryAsTheMiniProgram() {
        let schedule = PadAboutContent.Schedule(startedAt: 1_000_000, meanMonthMilliseconds: 100_000)
        func date(_ months: Double) -> Date { Date(timeIntervalSince1970: (1_000_000 + months * 100_000) / 1000) }
        #expect(schedule.months(at: date(-1)) == 0)
        #expect(schedule.months(at: date(0.499)) == 0)
        #expect(schedule.months(at: date(0.5)) == 1)
        #expect(schedule.months(at: date(1.499)) == 1)
        #expect(schedule.months(at: date(1.5)) == 2)
        let token = PadAboutContent.Investment.Item(id: "tokens", title: "", body: "", amount: 0, monthlyAmount: 2000)
        let unknown = PadAboutContent.Investment.Item(id: "staff", title: "", body: "", amount: nil, monthlyAmount: nil)
        let annual = PadAboutContent.Investment.Item(id: "server", title: "", body: "", amount: 1200, monthlyAmount: nil)
        let group = PadAboutContent.Investment.Group(id: "test", title: "", items: [token, unknown, annual])
        #expect(group.amount(months: 3) == 7200)
        #expect(unknown.amount(months: 3) == nil)
        #expect(PadAboutContent.money(7200, language: .chinese) == "约¥7,200")
        #expect(PadAboutContent.money(nil, language: .english) == "Not totaled")
    }
}
