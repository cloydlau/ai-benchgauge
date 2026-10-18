import Foundation
import LeaderboardCore
import Testing

struct CodexTaskStatusPreferenceTests {
    @Test func existingInstallDefaultsOffWithoutWritingAChoice() throws {
        let suite = "task-toggle-default-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Existing unrelated settings must not opt an upgraded install in.
        defaults.set("window", forKey: PanelModePreference.userDefaultsKey)
        #expect(!CodexTaskStatusPreference.load(from: defaults))
        #expect(defaults.object(forKey: CodexTaskStatusPreference.userDefaultsKey) == nil)
    }

    @Test func bothChoicesPersistWhenPreferencesAreReloaded() throws {
        let suite = "task-toggle-persistence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for enabled in [true, false, true, false] {
            CodexTaskStatusPreference.save(enabled, to: defaults)
            let reloaded = try #require(UserDefaults(suiteName: suite))
            #expect(CodexTaskStatusPreference.load(from: reloaded) == enabled)
            #expect(reloaded.object(forKey: CodexTaskStatusPreference.userDefaultsKey) as? Bool == enabled)
        }
    }
}
