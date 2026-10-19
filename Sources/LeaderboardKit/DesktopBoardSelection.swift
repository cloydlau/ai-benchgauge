/// Desktop visibility is stored per category. Missing or obsolete preferences
/// restore all sources; an empty dashboard is never a valid selection.
public enum DesktopBoardSelection {
    public static func kinds(for category: LeaderboardCategory, saved: [String]?) -> [LeaderboardKind] {
        let kinds = category.boardKinds.filter { saved?.contains($0.rawValue) ?? true }
        return kinds.isEmpty ? category.boardKinds : kinds
    }

    public static func toggling(_ kind: LeaderboardKind, in category: LeaderboardCategory, saved: [String]?) -> [String] {
        let current = kinds(for: category, saved: saved)
        guard category.boardKinds.contains(kind) else { return current.map(\.rawValue) }
        let next = current.contains(kind) ? current.filter { $0 != kind } : current + [kind]
        guard !next.isEmpty else { return current.map(\.rawValue) }
        return category.boardKinds.filter { next.contains($0) }.map(\.rawValue)
    }
}
