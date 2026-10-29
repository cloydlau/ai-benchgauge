import Foundation
import Testing
@testable import LeaderboardKit

@Test func aaSpeedOrderingAndMissingValues() {
    let first = LeaderboardEntry(rank: 1, name: "A", score: 90, speed: 100)
    let second = LeaderboardEntry(rank: 2, name: "B", score: 80, speed: 200)
    let missing = LeaderboardEntry(rank: 3, name: "C", score: 70)
    #expect([first, second, missing].sorted { LeaderboardPresentation.speedPrecedes($0, $1, kind: .artificialAnalysis) }.map(\.rank) == [2, 1, 3])
    #expect([first, second, missing].sorted { LeaderboardPresentation.speedPrecedes($0, $1, kind: .artificialAnalysisCodingAgent) }.map(\.rank) == [1, 2, 3])
    #expect(LeaderboardPresentation.speedText(nil) == "—")
    #expect(LeaderboardEntry(rank: 1, name: "bad", score: 1, speed: -1).speed == nil)
}
