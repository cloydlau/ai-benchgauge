import Foundation

/// Remembers the last selected leaderboard category outside the board cache,
/// so a refresh can rewrite leaderboards.json without touching this choice.
public enum CategoryPreference {
    public static let userDefaultsKey = "selectedLeaderboardCategory"

    public static func load(from defaults: UserDefaults = .standard) -> LeaderboardCategory {
        guard let raw = defaults.string(forKey: userDefaultsKey) else {
            return .general
        }
        guard let category = LeaderboardCategory(rawValue: raw) else {
            defaults.removeObject(forKey: userDefaultsKey)
            return .general
        }
        return category
    }

    public static func save(_ category: LeaderboardCategory, to defaults: UserDefaults = .standard) {
        defaults.set(category.rawValue, forKey: userDefaultsKey)
    }
}
