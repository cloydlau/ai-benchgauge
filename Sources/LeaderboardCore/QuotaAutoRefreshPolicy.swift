import Foundation

public enum QuotaAutoRefreshPolicy {
    public static let activeInterval: TimeInterval = 5 * 60
    public static let userActivityWindow: TimeInterval = 60

    private static let codexBundleIdentifiers: Set<String> = [
        "com.openai.codex",
    ]

    public static func isCodexBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return codexBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func shouldRefreshAutomatically(
        now: Date,
        lastAttemptAt: Date?,
        isCodexRunning: Bool,
        secondsSinceLastUserInput: TimeInterval?
    ) -> Bool {
        guard isCodexRunning,
              let secondsSinceLastUserInput,
              secondsSinceLastUserInput >= 0,
              secondsSinceLastUserInput <= userActivityWindow else {
            return false
        }
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= activeInterval
    }
}
