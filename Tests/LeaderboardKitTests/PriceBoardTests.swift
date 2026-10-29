import Foundation
import Testing
@testable import LeaderboardKit

@Test func priceCatalogRoundTripPreservesProviderAndOutput() throws {
    let json = #"{"kind":"openRouterPrice","title":"OpenRouter","fetchedAt":"2026-10-28T00:00:00Z","entries":[{"rank":1,"name":"Model","modelID":"a/model","organization":"a","provider":"OpenRouter","score":1,"outputPriceUSD":4}]}"#
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let board = try decoder.decode(Leaderboard.self, from: Data(json.utf8))
    #expect(board.kind == .openRouterPrice)
    #expect(board.entries[0].provider == "OpenRouter")
    #expect(board.entries[0].outputPriceUSD == 4)
    #expect(LeaderboardPresentation.scoreText(board.entries[0].score, kind: board.kind) == "$1.00")
    #expect(LeaderboardCategory.allCases.prefix(3) == [.usage, .general, .coding])
}

@Test func priceDirectionPreservesValuesAndReassignsRanks() {
    let entries = [
        LeaderboardEntry(rank: 1, name: "Free", score: 0, outputPriceUSD: 0),
        LeaderboardEntry(rank: 2, name: "Low", score: 3, outputPriceUSD: 2),
        LeaderboardEntry(rank: 3, name: "High", score: 3, outputPriceUSD: 9)
    ]
    let descending = LeaderboardPresentation.priceOrdered(entries)
    #expect(descending.map(\.name) == ["High", "Low", "Free"])
    #expect(descending.map(\.rank) == [1, 2, 3])
    #expect(LeaderboardPresentation.priceOrdered(entries, ascending: true).map(\.name) == ["Free", "Low", "High"])
    #expect(entries.map(\.rank) == [1, 2, 3])
}
