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

@Test func aaSpeedTiesAndMissingSpeedsRetainOriginalRanks() {
    let missingFirst = LeaderboardEntry(rank: 1, name: "Missing first", score: 90)
    let missingLast = LeaderboardEntry(rank: 4, name: "Missing last", score: 60)
    let measured = LeaderboardEntry(rank: 2, name: "Measured", score: 80, speed: 12)
    let tied = LeaderboardEntry(rank: 3, name: "Tied", score: 70, speed: 12)
    for kind in [LeaderboardKind.artificialAnalysis, .artificialAnalysisCodingAgent] {
        #expect(LeaderboardPresentation.speedPrecedes(missingFirst, missingLast, kind: kind))
        #expect(!LeaderboardPresentation.speedPrecedes(missingLast, missingFirst, kind: kind))
        #expect(!LeaderboardPresentation.speedPrecedes(missingFirst, measured, kind: kind))
        #expect(LeaderboardPresentation.speedPrecedes(measured, missingFirst, kind: kind))
        #expect(LeaderboardPresentation.speedPrecedes(measured, tied, kind: kind))
        #expect(!LeaderboardPresentation.speedPrecedes(tied, measured, kind: kind))
    }
    #expect(LeaderboardPresentation.speedText(1.24) == "1.2")
    #expect(LeaderboardPresentation.speedText(12) == "12")
    for invalid in [0.0, -1, .nan, .infinity] {
        #expect(LeaderboardPresentation.speedText(invalid) == "—")
    }
}
