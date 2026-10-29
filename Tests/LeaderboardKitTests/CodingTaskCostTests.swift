import Foundation
import Testing
@testable import LeaderboardKit

@Test func codingTaskCostParsingKeepsIndexMeanAndRejectsNonPrices() throws {
    let values: [Any] = [9.48, 0, 0.005, NSNull(), -1, "2", true, false, ["bad": 1], 12.7]
    let records: [[String: Any]] = values.enumerated().map { index, value in
        ["displayLabel": "Model \(index)", "indexScore": Double(90 - index) / 100,
         "mean": ["costUsd": value], "sums": ["costUsd": 99999],
         "evals": [["mean": ["costUsd": 777]]]]
    }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: records), as: UTF8.self)
    let quoted = String(decoding: try JSONSerialization.data(withJSONObject: [json]), as: UTF8.self).dropFirst().dropLast()
    let board = try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: "<script>self.__next_f.push([1,\(quoted)])</script>")
    #expect(board.entries.map(\.taskCostUSD) == [9.48, 0, 0.005, nil, nil, nil, nil, nil, nil, 12.7])
    let restored = try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board))
    #expect(restored == board)
}

@Test func taskCostOrderingRetainsRanksMovementAndScoresWithUnknownLast() {
    let entries = [
        LeaderboardEntry(rank: 1, name: "Strong", score: 90, organization: "OpenAI", rankChange: .init(delta: 2), taskCostUSD: 9.48),
        LeaderboardEntry(rank: 2, name: "Unknown", score: 80, organization: "Anthropic"),
        LeaderboardEntry(rank: 3, name: "Cheap", score: 70, organization: "OpenAI", taskCostUSD: 0.005),
        LeaderboardEntry(rank: 4, name: "Free", score: 60, organization: "Google", taskCostUSD: 0),
        LeaderboardEntry(rank: 5, name: "Tied cost", score: 50, organization: "Google", taskCostUSD: 0.005),
    ]
    let ordered = LeaderboardPresentation.orderedByTaskCost(entries, enabled: true)
    #expect(ordered.map(\.rank) == [4, 3, 5, 1, 2])
    #expect(ordered.first(where: { $0.rank == 1 }) == entries[0])
    #expect(!LeaderboardPresentation.taskCostPrecedes(entries[0], entries[0]))
    #expect(LeaderboardPresentation.orderedByTaskCost(entries, enabled: false) == entries)
    let companies = CompanyLeaderboard.rank(entries)
    #expect(companies.first(where: { $0.entry.name == "OpenAI" })?.entry.taskCostUSD == 9.48)
    #expect(companies.first(where: { $0.entry.name == "Anthropic" })?.entry.taskCostUSD == nil)
    #expect([nil, -.infinity, .nan, -1, 0, 0.0001, 0.005, 9.48].map(LeaderboardPresentation.taskCostText) == ["—", "—", "—", "—", "$0", "<$0.001", "$0.005", "$9.48"])
}

@Test func taskCostChangesAdvanceContentTimestampWithoutChangingCapability() {
    let oldDate = Date(timeIntervalSince1970: 1_000)
    let old = Leaderboard(kind: .artificialAnalysisCodingAgent, title: "AA", fetchedAt: oldDate, entries: [
        LeaderboardEntry(rank: 1, name: "A", score: 90, taskCostUSD: 2)
    ])
    let new = Leaderboard(kind: old.kind, title: old.title, fetchedAt: oldDate.addingTimeInterval(86_400), entries: [
        LeaderboardEntry(rank: 1, name: "A", score: 90, taskCostUSD: 3)
    ])
    #expect(new.preservingContentTimestamp(from: old).contentUpdatedAt == new.fetchedAt)
    #expect(new.entries[0].rank == old.entries[0].rank)
    for language in AppLanguage.allCases {
        #expect(LeaderboardPresentation.sourceHelp(old.kind, language: language, board: new).contains(LeaderboardPresentation.taskCostHelp(language: language)))
    }
}
