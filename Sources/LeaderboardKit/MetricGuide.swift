import Foundation

/// The hint is stored per source on this device, independently of rankings or sharing.
public enum MetricGuide {
    private static let key = "metricGuideSeenSources"

    public static func hasSeen(_ kind: LeaderboardKind, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(kind.rawValue)
    }

    public static func markSeen(_ kind: LeaderboardKind, defaults: UserDefaults = .standard) {
        guard kind.supportsAACost else { return }
        var seen = Set(defaults.stringArray(forKey: key) ?? [])
        guard seen.insert(kind.rawValue).inserted else { return }
        defaults.set(seen.sorted(), forKey: key)
    }

    public static func label(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Click to switch"
        case .chinese: "点击切换"
        case .traditionalChinese: "點擊切換"
        }
    }
}
