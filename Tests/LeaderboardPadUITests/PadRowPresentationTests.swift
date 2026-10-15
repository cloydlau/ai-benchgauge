import Foundation
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func longBoardPresentationIsReusedUntilDataOrFiltersChange() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "boards.json"))
    let entries = (1...5000).map { rank in
        LeaderboardEntry(rank: rank, name: "Model \(rank)", score: Double(10000 - rank),
            organization: "Maker \(rank)", openness: rank.isMultiple(of: 2) ? .open : .closed)
    }
    cache.save(LeaderboardSnapshot(boards: [.arenaText: Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)]))
    let name = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache)
    let first = store.rowPresentation(for: .arenaText)
    #expect(first.rows.count == 5000)
    #expect(first.rows.last?.rank == 5000)
    #expect(first === store.rowPresentation(for: .arenaText))
    store.appearance = "dark"
    #expect(first === store.rowPresentation(for: .arenaText))
    store.setOpennessFilter(.open, for: .arenaText)
    let filtered = store.rowPresentation(for: .arenaText)
    #expect(filtered !== first)
    #expect(filtered.rows.count == 2500)
    #expect(filtered.rows.last?.rank == 5000)
    store.grouping = .company
    let company = store.rowPresentation(for: .arenaText)
    #expect(company.rows.count == 2500)
    #expect(company.rows.last?.name == "Maker 5000")
    store.language = .english
    #expect(company !== store.rowPresentation(for: .arenaText))
    store.setCountryFilter(.country(.unitedStates), for: .arenaText)
    #expect(store.rowPresentation(for: .arenaText).rows.isEmpty)
}
