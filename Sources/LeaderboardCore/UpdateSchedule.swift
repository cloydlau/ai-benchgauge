import Foundation

public struct UpdateSchedule: Equatable, Sendable {
    public let dailyRunAt: Date
    public let retryAfterFailureAt: Date?
    public let giveUpAt: Date

    public init(
        dailyRunAt: Date,
        retryAfterFailureAt: Date? = nil,
        giveUpAt: Date
    ) {
        self.dailyRunAt = dailyRunAt
        self.retryAfterFailureAt = retryAfterFailureAt
        self.giveUpAt = giveUpAt
    }

    public static func initial(now: Date = Date(), calendar: Calendar = .current) -> UpdateSchedule {
        UpdateSchedule(
            dailyRunAt: nextDailyRun(after: now, calendar: calendar),
            giveUpAt: startOfNextDay(now, calendar: calendar)
        )
    }

    public static func afterSuccess(now: Date = Date(), calendar: Calendar = .current) -> UpdateSchedule {
        UpdateSchedule(
            dailyRunAt: nextDailyRun(after: now, calendar: calendar),
            giveUpAt: startOfNextDay(nextDailyRun(after: now, calendar: calendar), calendar: calendar)
        )
    }

    public func schedulingRetry(now: Date = Date(), calendar: Calendar = .current) -> UpdateSchedule {
        UpdateSchedule(
            dailyRunAt: dailyRunAt,
            retryAfterFailureAt: now.addingTimeInterval(3600),
            giveUpAt: giveUpAt
        )
    }

    public func givingUp(calendar: Calendar = .current) -> UpdateSchedule {
        UpdateSchedule(
            dailyRunAt: UpdateSchedule.nextDailyRun(after: giveUpAt, calendar: calendar),
            giveUpAt: UpdateSchedule.startOfNextDay(
                UpdateSchedule.nextDailyRun(after: giveUpAt, calendar: calendar),
                calendar: calendar
            )
        )
    }

    public func isDue(now: Date = Date()) -> Bool {
        if now >= giveUpAt { return true }
        if let retryAfterFailureAt { return now >= retryAfterFailureAt }
        return now >= dailyRunAt
    }

    private static func nextDailyRun(after date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        components.second = 0

        guard let run = calendar.date(from: components), run > date else {
            var nextComponents = components
            nextComponents.day? += 1
            return calendar.date(from: nextComponents) ?? date
        }
        return run
    }

    private static func startOfNextDay(_ date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.day? += 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }
}
