import Foundation
import LeaderboardCore
import Testing

struct QuotaAutoRefreshPolicyTests {
    @Test
    func automaticRefreshRequiresRecentUserInput() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastAttempt = now.addingTimeInterval(-QuotaAutoRefreshPolicy.activeInterval)

        #expect(QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: lastAttempt,
            isCodexRunning: true,
            secondsSinceLastUserInput: 60
        ))
        #expect(!QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: lastAttempt,
            isCodexRunning: true,
            secondsSinceLastUserInput: 60.1
        ))
        #expect(!QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: lastAttempt,
            isCodexRunning: true,
            secondsSinceLastUserInput: nil
        ))
    }

    @Test
    func automaticRefreshRequiresCodexAndElapsedInterval() {
        let now = Date(timeIntervalSince1970: 20_000)

        #expect(QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: nil,
            isCodexRunning: true,
            secondsSinceLastUserInput: 10
        ))
        #expect(!QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: nil,
            isCodexRunning: false,
            secondsSinceLastUserInput: 10
        ))
        #expect(!QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: now.addingTimeInterval(-(QuotaAutoRefreshPolicy.activeInterval - 1)),
            isCodexRunning: true,
            secondsSinceLastUserInput: 10
        ))
        #expect(QuotaAutoRefreshPolicy.shouldRefreshAutomatically(
            now: now,
            lastAttemptAt: now.addingTimeInterval(-QuotaAutoRefreshPolicy.activeInterval),
            isCodexRunning: true,
            secondsSinceLastUserInput: 10
        ))
    }

    @Test
    func recognizesOnlyTheCodexDesktopBundle() {
        #expect(QuotaAutoRefreshPolicy.isCodexBundleIdentifier("com.openai.codex"))
        #expect(!QuotaAutoRefreshPolicy.isCodexBundleIdentifier("com.openai.chat"))
        #expect(!QuotaAutoRefreshPolicy.isCodexBundleIdentifier(nil))
    }
}
