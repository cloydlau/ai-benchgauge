import Foundation
@testable import LeaderboardCore
import Testing

struct UpdateScheduleTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func date(_ hour: Int, day: Int = 13) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func dailyRunAndRetryDeadlines() {
        let before = UpdateSchedule.initial(now: date(8), calendar: calendar)
        #expect(before.dailyRunAt == date(9))
        #expect(before.giveUpAt == date(0, day: 14))
        #expect(!before.isDue(now: date(8)))
        #expect(before.isDue(now: date(9)))
        #expect(before.isDue(now: date(0, day: 14)))
        let next = UpdateSchedule.afterSuccess(now: date(10), calendar: calendar)
        #expect(next.dailyRunAt == date(9, day: 14))
        #expect(next.giveUpAt == date(0, day: 15))
        let retry = before.schedulingRetry(now: date(10), calendar: calendar)
        #expect(retry.retryAfterFailureAt == date(11))
        #expect(!retry.isDue(now: date(10)))
        #expect(retry.isDue(now: date(11)))
        #expect(retry.givingUp(calendar: calendar).dailyRunAt == date(9, day: 14))
        #expect(UpdateSchedule.initial().retryAfterFailureAt == nil)
        #expect(UpdateSchedule.afterSuccess().retryAfterFailureAt == nil)
        #expect(before.schedulingRetry().retryAfterFailureAt != nil)
        #expect(before.givingUp().retryAfterFailureAt == nil)
        _ = before.isDue()
    }

    @Test func calendarConstructionFailureKeepsTheExistingDeadline() {
        let now = date(8)
        let schedule = UpdateSchedule.initial(now: now, calendar: calendar, makeDate: { _ in nil })
        #expect(schedule.dailyRunAt == now)
        #expect(schedule.giveUpAt == now)
    }
}
