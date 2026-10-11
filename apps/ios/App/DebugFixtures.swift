#if DEBUG
import Foundation
import LeaderboardKit
import LeaderboardPadUI

/// Deterministic simulator UI tests. Never enabled in a Release build.
@MainActor
enum DebugFixtures {
    static func makeStoreIfRequested() -> LeaderboardPadStore? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return nil }
        let name = "ai-benchgauge-ui-tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let language: AppLanguage = arguments.contains("--preview-zh") ? .chinese : .english
        language.save(to: defaults)
        if arguments.contains("--preview-companies") { GroupingPreference.save(.company, to: defaults) }
        let cache = LeaderboardCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "ui-test-boards.json"))
        let full = arguments.contains("--full-board")
        let wrappedNames = arguments.contains("--wrapped-names")
        let arenaScores = arguments.contains("--arena-scores")
        let fetchedAt = arguments.contains("--recent-update") ? Date().addingTimeInterval(-29 * 60)
            : Date(timeIntervalSince1970: 1_700_000_000)
        let pending = arguments.contains("--pending-boards")
        let boards = pending ? [:] : Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map {
            ($0, board($0, full: full, wrappedNames: wrappedNames, arenaScores: arenaScores, fetchedAt: fetchedAt))
        })
        cache.save(LeaderboardSnapshot(boards: boards))
        let offline = arguments.contains("--offline") || pending
        return LeaderboardPadStore(defaults: defaults, cache: cache, service: LeaderboardService { kind in
            if offline { throw URLError(.notConnectedToInternet) }
            return board(kind, full: full, wrappedNames: wrappedNames, arenaScores: arenaScores, fetchedAt: fetchedAt)
        })
    }
    nonisolated private static func board(_ kind: LeaderboardKind, full: Bool = false, wrappedNames: Bool = false, arenaScores: Bool = false, fetchedAt: Date) -> Leaderboard {
        let scores: [Double] = arenaScores && kind.sourcePrefix == "Arena" ? [1499.9, 1234.5, 999.9] : [90, 89, 88]
        let entries = [
            LeaderboardEntry(rank: 1, name: full ? "GPT Fixture — Very Long Model Name With Extended Reasoning And Multilingual Capabilities" : "GPT Fixture", score: scores[0], organization: "OpenAI"),
            LeaderboardEntry(rank: 2, name: wrappedNames ? "DeepSeek Fixture — Advanced Reasoning With Multilingual Tool Use And Long Context" : "DeepSeek Fixture", score: scores[1], organization: "DeepSeek"),
            LeaderboardEntry(rank: 3, name: wrappedNames ? "Claude Fixture — Advanced Reasoning With Multilingual Tool Use And Long Context" : "Claude Fixture", score: scores[2], organization: "Anthropic"),
        ] + (full ? (4...20).map { rank in
            LeaderboardEntry(rank: rank, name: "Fixture Model \(rank)", score: Double(90 - rank), organization: rank == 20 ? "Unknown Developer" : "Google")
        } : [])
        return Leaderboard(kind: kind, title: "Fixture", fetchedAt: fetchedAt, entries: entries)
    }
}
#endif
