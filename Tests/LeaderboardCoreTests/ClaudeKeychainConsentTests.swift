import Foundation
import LeaderboardCore
import Testing

struct ClaudeKeychainConsentTests {
    @Test
    func testConsentIsUndeterminedUntilTheUserChooses() {
        let suite = "ClaudeKeychainConsentTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return recordFailure("Could not create test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ClaudeKeychainConsentPreference.load(from: defaults) == .notDetermined)

        ClaudeKeychainConsentPreference.save(.allowed, to: defaults)
        #expect(ClaudeKeychainConsentPreference.load(from: defaults) == .allowed)

        ClaudeKeychainConsentPreference.save(.denied, to: defaults)
        #expect(ClaudeKeychainConsentPreference.load(from: defaults) == .denied)

        defaults.set("unexpected", forKey: ClaudeKeychainConsentPreference.userDefaultsKey)
        #expect(ClaudeKeychainConsentPreference.load(from: defaults) == .notDetermined)
    }
}
