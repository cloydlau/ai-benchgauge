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
        let brands = arguments.contains("--brand-discovery")
        let fetchedAt = arguments.contains("--recent-update") ? Date().addingTimeInterval(-29 * 60)
            : Date(timeIntervalSince1970: 1_700_000_000)
        let pending = arguments.contains("--pending-boards")
        let boards = pending ? [:] : Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map {
            ($0, board($0, full: full, wrappedNames: wrappedNames, arenaScores: arenaScores, brands: brands, fetchedAt: fetchedAt))
        })
        cache.save(LeaderboardSnapshot(boards: boards))
        let offline = arguments.contains("--offline") || pending
        return LeaderboardPadStore(defaults: defaults, cache: cache, service: LeaderboardService { kind in
            if offline { throw URLError(.notConnectedToInternet) }
            return board(kind, full: full, wrappedNames: wrappedNames, arenaScores: arenaScores, brands: brands, fetchedAt: fetchedAt)
        })
    }
    nonisolated private static func board(_ kind: LeaderboardKind, full: Bool = false, wrappedNames: Bool = false, arenaScores: Bool = false, brands: Bool = false, fetchedAt: Date) -> Leaderboard {
        let scores: [Double] = arenaScores && kind.sourcePrefix == "Arena" ? [1499.9, 1234.5, 999.9] : [90, 89, 88]
        let modelEntries = ProcessInfo.processInfo.environment["BENCHGAUGE_UI_MODEL_ENTRIES"]
            .flatMap { try? JSONDecoder().decode([LeaderboardEntry].self, from: Data($0.utf8)) }
        let entries: [LeaderboardEntry] = modelEntries ?? (brands ? [
            LeaderboardEntry(rank: 1, name: "New Maker Video Model — Extended Multilingual Edition", score: scores[0], organization: "New Maker", brand: OrganizationBrand(key: "newmaker", colorHex: "#319FA8", pngData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAABxVBMVEVMaXEkkbYzmbIwnqcwnqgxnqc/f78xnqgqqqoxnqcxnqgxn6dVqqoxnqgwn6gzmaUznaY/n58xnqgwnqcwnqg1oa4xn6cyoKYxn6cwn6gtnKoxn6cwnqgxnqgxnqcuoqIxnqgxn6cxnKYxn6cwn6gxn6cwnqcwn6cxn6cyn6gwn6cvn6gwnqcxn6gxnaYwnqgvn6Yuoacwn6gxnqgwn6cwn6gxoKYwn6gwn6gxnKYxnqgzo6Mwn6czmZkwn6gxn6cxnqgwn6c4qqownqgwn6gxnqgwnqcwn6cyn6gwnaozoKcwnqgwnqgxn6gxnqgqlKozn6UtmqMqm6o0nqcxn6gyoKownqcxnqcvoKownqg0naUwn6gxnqcxn6j////8/f7w+PmNys85o6v9/v7Z7e+23eBMrLRmuL+Lyc6x295Kq7M3oqtqusDW7O5SrraBxMru9/gzoKn+//88pK3Y7e/v9/g2oarI5ejm8/SVztJuu8Jhtrw4oquw2t7R6uwyn6i84ONHqbGm1tmMys9zvsRLq7NftLuk1NiRzNFitr2f0tZGqbHr9vas2Nxds7o0oalCp6+03N/2+/uWztN7wcf4/Py73+KR21E9AAAAXXRSTlMABwrsmfkE3wbeTe0D9OsUNwiC4YQTm1HqcyfA8e7vC+nzGtCIhk/y+HDNUKmqca5LJsvOg91O4K00kRnDBcKAnNsJ3OK/kpg4FSM1ooWBDCgcEh3jM5dyG5Qi+lLCb010AAAACXBIWXMAAAsTAAALEwEAmpwYAAACeklEQVRYw+2X91/TQBjG0zaldGEtpdBCEcqSjbJFQAUUxL3XpSAiuECWe4ELBw4U/15JUq+55MZ7H3/l+S13+T6fy5Mb7ynKjpjKiyTiA/7UdW/KPxBPRPLk6Pzi1jpEqKynMR+Mj8U8iCJPxy4Qfro6jBgK1+wR843DiKPCWgG++wAS6ISbx5+tQkK1p9n88SEEUHeSxZ8pQSBV7KPzV3wIqAvnqflVIbAaXBQDFUnoqpMvRlIK2Hm3T86g0D4nq5GkYiRfVClrECZX1kkA8vED8XiKWP8eMT+pZdatzwXW/eGGmJ/JaJr284Wlpcti0Crk765oul79yDU1W/a/MhF/74HBa7du5trKQ9hgVDiAOyY/cdva2IsNEuIADU3dJ1pbsMEhSIDbmiWbVWxwUBDgQ5OftrWXYgOfdICG/NggaGd+v1kQBGhMJWzgtfXMTmkbggB17WUYvP6sA7/4AZIGxCd8f2kAi/PcAMlPIEJ89Dg75ne8AMkQyd+4tGxCW885AZK/MU52fHmSxebYAeo6hg0u23rmJkzwazbASfoEqccGEXvXt03NomnGDLvIWc7PMjmeGiC5nJUeR+/84j9+5T1jAE38U+Vpls/MQM4W2qa6Zhq8ZfEl/dZtucP5wsIfXoAIDQoPFn1KsgJ0HCxKDeWdpWX6DDQUhRyuq5/gh6tSK3c0tjkLhEsy/FFaidMO5/fTShwlDa4x/H30Mi1Z8X9lnqJcOwzhfUl2qZpuAHx/H69YdgmLbdUlqNcD3dz42sQXBneMWXDVRY+A7ixF0QLq+h08B790dTWXk3SqKdAvd3ELjbeopZ1BrzfYOaLW94Z2LsJs/QUdf3odLf4uFgAAAABJRU5ErkJggg=="))),
            LeaderboardEntry(rank: 2, name: "Unlisted Studio Video Model", score: scores[1], organization: "Unlisted Studio", brand: OrganizationBrand(key: "unlistedstudio", colorHex: "#8C6BB1")),
            LeaderboardEntry(rank: 3, name: "GPT Fixture", score: scores[2], organization: "OpenAI", openness: .closed),
        ] : [
            LeaderboardEntry(rank: 1, name: full ? "GPT Fixture — Very Long Model Name With Extended Reasoning And Multilingual Capabilities" : "GPT Fixture", score: scores[0], organization: "OpenAI", openness: .closed),
            LeaderboardEntry(rank: 2, name: wrappedNames ? "DeepSeek Fixture — Advanced Reasoning With Multilingual Tool Use And Long Context" : "DeepSeek Fixture", score: scores[1], organization: "DeepSeek", openness: .open),
            LeaderboardEntry(rank: 3, name: wrappedNames ? "Claude Fixture — Advanced Reasoning With Multilingual Tool Use And Long Context" : "Claude Fixture", score: scores[2], organization: "Anthropic"),
        ] + (full ? (4...20).map { rank in
            LeaderboardEntry(rank: rank, name: "Fixture Model \(rank)", score: Double(90 - rank), organization: rank == 20 ? "Unknown Developer" : "Google")
        } : []))
        let sourceDates = ProcessInfo.processInfo.arguments.contains("--source-times")
        let sourceDate = sourceDates && (kind.sourcePrefix == "Arena" || kind == .artificialAnalysisCodingAgent)
            ? fetchedAt.addingTimeInterval(-3600) : nil
        return Leaderboard(kind: kind, title: "Fixture", sourceUpdatedAt: sourceDate, fetchedAt: fetchedAt, entries: entries)
    }
}
#endif
