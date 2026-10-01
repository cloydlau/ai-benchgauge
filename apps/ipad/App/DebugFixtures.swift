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
        let cache = LeaderboardCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "ui-test-boards.json"))
        let boards = Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { ($0, board($0, full: arguments.contains("--full-board"))) })
        cache.save(LeaderboardSnapshot(boards: boards))
        let offline = arguments.contains("--offline")
        let full = arguments.contains("--full-board")
        return LeaderboardPadStore(defaults: defaults, cache: cache, service: LeaderboardService { kind in
            if offline { throw URLError(.notConnectedToInternet) }
            return board(kind, full: full)
        })
    }
    nonisolated private static func board(_ kind: LeaderboardKind, full: Bool = false) -> Leaderboard {
        let entries = [
            LeaderboardEntry(rank: 1, name: full ? "GPT Fixture — Very Long Model Name With Extended Reasoning And Multilingual Capabilities" : "GPT Fixture", score: 90, organization: "OpenAI"),
            LeaderboardEntry(rank: 2, name: "DeepSeek Fixture", score: 89, organization: "DeepSeek"),
            LeaderboardEntry(rank: 3, name: "Claude Fixture", score: 88, organization: "Anthropic"),
        ] + (full ? (4...20).map { rank in
            LeaderboardEntry(rank: rank, name: "Fixture Model \(rank)", score: Double(90 - rank), organization: rank == 20 ? "Unknown Developer" : "Google")
        } : [])
        return Leaderboard(kind: kind, title: "Fixture", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), entries: entries)
    }
}
#endif
