import Foundation
import Testing
import LeaderboardKit

@Test func contentTimestampRulesSurviveCacheCodingAndMatchSharedFixtures() throws {
    struct Sample: Decodable {
        let name: String
        let previous: Leaderboard?
        let next: Leaderboard
        let expected: Date
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let samples = try decoder.decode([Sample].self,
        from: Data(contentsOf: root.appendingPathComponent("fixtures/content-timestamps.json")))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    for sample in samples {
        let result = sample.next.preservingContentTimestamp(from: sample.previous)
        #expect(result.contentTimestamp == sample.expected, "\(sample.name)")
        let restored = try decoder.decode(Leaderboard.self, from: encoder.encode(result))
        #expect(restored.contentTimestamp == sample.expected, "\(sample.name) offline")
        if sample.next.canReplace(sample.previous) {
            #expect(result.fetchedAt == sample.next.fetchedAt)
        }
        let parts = LeaderboardPresentation.sourceTimeParts(restored, language: .english)
        if restored.sourceUpdatedAt == nil || restored.kind.isShareUsage {
            #expect(parts.value == LeaderboardPresentation.calendarTimestamp(sample.expected, language: .english))
        }
    }
}

@Test func contentTimestampServiceRetainsDuplicatesButAcceptsNewScores() async {
    let first = Date(timeIntervalSince1970: 1_700_000_000)
    let previous = Leaderboard(kind: .epochECI, title: "Fixture", fetchedAt: first,
        entries: [LeaderboardEntry(rank: 1, name: "Model", score: 90)])
    for score in [90.0, 91.0] {
        let next = Leaderboard(kind: .epochECI, title: "Fixture", fetchedAt: first.addingTimeInterval(3600),
            entries: [LeaderboardEntry(rank: 1, name: "Model", score: score)])
        let result = await LeaderboardService(fetch: { _ in next }).refresh([.epochECI],
            keeping: LeaderboardSnapshot(boards: [.epochECI: previous]))
        #expect(result.snapshot.boards[.epochECI]?.contentTimestamp == (score == 90 ? first : next.fetchedAt))
    }
}
