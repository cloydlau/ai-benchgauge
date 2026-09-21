import Foundation

public enum ModelMatcher {
    public static func canonicalModelID(for entry: LeaderboardEntry) -> String? {
        canonicalModelID(from: entry.name)
    }

    /// Canonical ID with the effort qualifier removed, used as a fallback when
    /// two leaderboards list the same model at different effort levels.
    public static func baseModelID(for entry: LeaderboardEntry) -> String? {
        guard let canonical = canonicalModelID(from: entry.name) else { return nil }
        // Longest first so "xhigh" wins over its own suffix "high".
        for effort in effortWords.sorted(by: { $0.count > $1.count }) where canonical.hasSuffix(effort) {
            let base = String(canonical.dropLast(effort.count))
            if !base.isEmpty { return base }
        }
        return canonical
    }

    public static func canonicalModelID(from name: String) -> String? {
        var value = name.lowercased()
        var effort: String?
        var retainedNumbers: [String] = []

        while let opening = value.firstIndex(of: Character("(")),
              let closing = value[opening...].firstIndex(of: Character(")")) {
            let parenthetical = String(value[value.index(after: opening)..<closing])
            let words = tokenize(parenthetical)

            if words.contains(where: { effortWords.contains($0) }) {
                effort = words.first { effortWords.contains($0) }
            } else {
                retainedNumbers.append(
                    contentsOf: words.filter { $0.allSatisfy { character in character.isNumber } }
                )
            }

            value.removeSubrange(opening...closing)
        }

        var words = tokenize(value)
        if let effort, !words.contains(effort) {
            words.append(effort)
        }
        words.append(contentsOf: retainedNumbers)

        let canonical = words.filter { !noiseWords.contains($0) }.joined()
        return canonical.isEmpty ? nil : canonical
    }

    private static let effortWords: Set<String> = [
        "max", "xhigh", "high", "medium", "low", "standard"
    ]

    private static let noiseWords: Set<String> = [
        "adaptive", "reasoning", "effort", "default", "fallback",
        "webdev", "codex", "harness", "public"
    ]

    private static func tokenize(_ value: String) -> [String] {
        value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
