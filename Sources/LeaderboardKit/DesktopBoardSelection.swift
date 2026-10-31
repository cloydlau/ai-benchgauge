/// Missing or obsolete preferences restore defaults; explicit empty categories stay hidden.
/// The minimum selection applies to the entire dashboard.
public enum DesktopBoardSelection {
    public static func kinds(for category: LeaderboardCategory, saved: [String]?) -> [LeaderboardKind] {
        guard let saved else { return category.defaultBoardKinds }
        let kinds = category.boardKinds.filter { saved.contains($0.rawValue) }
        return saved.isEmpty ? [] : kinds.isEmpty ? category.defaultBoardKinds : kinds
    }

    public static func categories(in selections: [String: [String]]) -> [LeaderboardCategory] {
        LeaderboardCategory.allCases.filter { !kinds(for: $0, saved: selections[$0.rawValue]).isEmpty }
    }

    public static func count(in selections: [String: [String]]) -> Int {
        LeaderboardCategory.allCases.reduce(0) { $0 + kinds(for: $1, saved: selections[$1.rawValue]).count }
    }

    public static func normalized(_ selections: [String: [String]]) -> [String: [String]] {
        let result = Dictionary(uniqueKeysWithValues: LeaderboardCategory.allCases.compactMap { category -> (String, [String])? in
            let selected = kinds(for: category, saved: selections[category.rawValue])
            return selected == category.defaultBoardKinds ? nil : (category.rawValue, selected.map(\.rawValue))
        })
        return count(in: result) > 0 ? result : [:]
    }

    public static func updating(_ selected: [LeaderboardKind], in category: LeaderboardCategory,
                                selections: [String: [String]]) -> [String: [String]] {
        let next = category.boardKinds.filter { selected.contains($0) }
        var result = selections
        result[category.rawValue] = next.map(\.rawValue)
        return count(in: result) > 0 ? normalized(result) : selections
    }

    public static func toggling(_ kind: LeaderboardKind, in category: LeaderboardCategory,
                                selections: [String: [String]]) -> [String: [String]] {
        guard category.boardKinds.contains(kind) else { return selections }
        let current = kinds(for: category, saved: selections[category.rawValue])
        return updating(current.contains(kind) ? current.filter { $0 != kind } : current + [kind],
                        in: category, selections: selections)
    }
}
