import Testing
import LeaderboardKit
@testable import LeaderboardPadUI

@MainActor @Test func aaCostViewUsesHighestPriceAcrossAllAAKinds() {
    for kind in [LeaderboardKind.artificialAnalysis, .artificialAnalysisCodingAgent, .artificialAnalysisTextToImage, .artificialAnalysisTextToVideo] {
        let board = Leaderboard(kind: kind, title: "AA", entries: [
            LeaderboardEntry(rank: 1, name: "Expensive", score: 99, taskCostUSD: 10),
            LeaderboardEntry(rank: 2, name: "Cheap", score: 90, taskCostUSD: 2.5),
            LeaderboardEntry(rank: 3, name: "Unknown", score: 80),
        ])
        let costs = PadRowPresentation(board: board, grouping: .model, country: .all, openness: .all, language: .english, costOrder: true)
        #expect(costs.rows.map(\.rank) == [1, 2, 3])
        #expect(costs.leaderScore == 10)
        #expect(LeaderboardPresentation.scoreShareText(2.5, leaderScore: costs.leaderScore) == "25%")
        #expect(costs.page(0..<1).leaderScore == 10)
    }
}
