import Foundation
import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func priceDirectionAndExportProjection() throws {
    let board = Leaderboard(kind: .openRouterPrice, title: "OpenRouter", entries: [
        LeaderboardEntry(rank: 1, name: "Cheap", score: 1, outputPriceUSD: 4),
        LeaderboardEntry(rank: 2, name: "Expensive", score: 9, outputPriceUSD: 10)
    ])
    let defaultRows = PadRowPresentation(board: board, grouping: .model, country: .all, openness: .all, language: .english)
    let ascending = PadRowPresentation(board: board, grouping: .model, country: .all, openness: .all, language: .english, priceAscending: true)
    #expect(defaultRows.rows.map(\.name) == ["Expensive", "Cheap"])
    #expect(ascending.rows.map(\.name) == ["Cheap", "Expensive"])
    #expect(defaultRows.rows.map(\.rank) == [1, 2])
    #expect(ascending.page(0..<1).rows.first?.outputPriceUSD == 4)
}
