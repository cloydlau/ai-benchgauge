import Foundation
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func taskCostOrderUsesPriceBaselineAndPreservesPaginatedExportRows() {
    let board = Leaderboard(kind: .artificialAnalysisCodingAgent, title: "AA", entries: [
        LeaderboardEntry(rank: 1, name: "Strong", score: 90, organization: "OpenAI", taskCostUSD: 9.48),
        LeaderboardEntry(rank: 2, name: "Unknown", score: 80, organization: "Anthropic"),
        LeaderboardEntry(rank: 3, name: "Cheap", score: 70, organization: "OpenAI", taskCostUSD: 0.005),
        LeaderboardEntry(rank: 4, name: "Zero", score: 60, organization: "Google", taskCostUSD: 0),
    ])
    let rows = PadRowPresentation(board: board, grouping: .model, country: .all, openness: .all, language: .english, costOrder: true)
    #expect(rows.rows.map(\.rank) == [1, 2, 3, 4])
    #expect(rows.leaderScore == 9.48)
    #expect(rows.page(0..<2).rows.map(\.taskCostUSD) == [9.48, nil])
    #expect(rows.page(0..<2).leaderScore == 9.48)
    let companies = PadRowPresentation(board: board, grouping: .company, country: .all, openness: .all, language: .english, costOrder: true)
    #expect(companies.rows.first(where: { $0.name == "OpenAI" })?.taskCostUSD == 9.48)
}

@MainActor @Test func frozenTaskCostExportRetainsTheSelectedOrderAndDoesNotFollowLaterChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "boards.json"))
    let board = Leaderboard(kind: .artificialAnalysisCodingAgent, title: "AA", entries: [
        LeaderboardEntry(rank: 1, name: "Strong", score: 90, organization: "OpenAI", taskCostUSD: 9),
        LeaderboardEntry(rank: 2, name: "Cheap", score: 70, organization: "Google", taskCostUSD: 0),
    ])
    cache.save(LeaderboardSnapshot(boards: [board.kind: board]))
    let suite = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = LeaderboardPadStore(defaults: defaults, cache: cache)
    let before = store.rowPresentation(for: board.kind)
    store.codingCostOrder = true
    #expect(before !== store.rowPresentation(for: board.kind))
    let frozen = LeaderboardPadStore(exporting: store)
    store.codingCostOrder = false
    #expect(frozen.codingCostOrder)
    #expect(frozen.rowPresentation(for: board.kind).rows.map(\.rank) == [1, 2])
    #expect(store.rowPresentation(for: board.kind).rows.map(\.rank) == [1, 2])
    #expect(frozen.rowPresentation(for: board.kind).page(0..<1).rows.first?.taskCostUSD == 9)
}
