import Foundation

/// Remembers the last model/company grouping outside the board cache, so a
/// refresh can rewrite leaderboards.json without touching this choice.
/// Company rows are derived locally, so restoring this does not fetch.
public enum GroupingPreference {
    public static let userDefaultsKey = "selectedLeaderboardGrouping"

    public static func load(from defaults: UserDefaults = .standard) -> LeaderboardGrouping {
        guard let raw = defaults.string(forKey: userDefaultsKey) else {
            return .model
        }
        guard let grouping = LeaderboardGrouping(rawValue: raw) else {
            defaults.removeObject(forKey: userDefaultsKey)
            return .model
        }
        return grouping
    }

    public static func save(_ grouping: LeaderboardGrouping, to defaults: UserDefaults = .standard) {
        defaults.set(grouping.rawValue, forKey: userDefaultsKey)
    }
}
