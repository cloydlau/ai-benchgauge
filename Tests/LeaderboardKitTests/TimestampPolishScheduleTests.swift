import Testing
@testable import LeaderboardKit

@Test func timestampPolishFollowsLoadCompletionCadenceAndSuspension() {
    var schedule = TimestampPolishSchedule()
    #expect(schedule.phase(at: 0) == nil)
    var changed = schedule.update(now: 0, ready: false)
    #expect(!changed)
    changed = schedule.update(now: 10, ready: true)
    #expect(changed)
    #expect(schedule.phase(at: 10) == 0)
    #expect(abs(schedule.phase(at: 10.55)! - 0.5) < 0.0001)
    #expect(schedule.phase(at: 9) == nil)
    #expect(schedule.phase(at: 11.2) == nil)
    changed = schedule.update(now: 39.999, ready: true)
    #expect(!changed)
    changed = schedule.update(now: 40, ready: true)
    #expect(changed)
    changed = schedule.update(now: 41, ready: false)
    #expect(!changed)
    // Finishing an unchanged refresh still starts a fresh pass.
    changed = schedule.update(now: 42, ready: true)
    #expect(changed)
    #expect(schedule.startedAt == 42)
    #expect(TimestampPolishSchedule.interval == 30)
    #expect(TimestampPolishSchedule.duration == 1.1)
}
