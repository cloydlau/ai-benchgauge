import Foundation
import Testing
import LeaderboardKit

@Test func countryFilteringPrecedesCompanyTopTwenty() {
    let entries = [LeaderboardEntry(rank: 1, name: "GPT", score: 100, organization: "OpenAI")]
        + (2...22).map { LeaderboardEntry(rank: $0, name: "Unknown model \($0)", score: Double(100 - $0), organization: "Unknown developer \($0)") }
    let board = Leaderboard(kind: .arenaText, title: "Fixture", entries: entries)
    let companies = LeaderboardPresentation.rows(board, grouping: .company, filter: .unknown)
    #expect(companies.count == 20)
    #expect(companies.first?.score == 98)
    #expect(LeaderboardPresentation.companies(board, filter: .unknown).map(\.entry) == companies)
    #expect(LeaderboardPresentation.countryFilters(board) == [.all, .country(.unitedStates), .unknown])
}

@Test func updateLabelUsesOldestVisibleSourceAndDesktopAgeThresholds() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let left = Leaderboard(kind: .artificialAnalysis, title: "AA", fetchedAt: now.addingTimeInterval(-3600), entries: [])
    let right = Leaderboard(kind: .arenaText, title: "Arena", fetchedAt: now, entries: [])
    let snapshot = LeaderboardSnapshot(boards: [.artificialAnalysis: left, .arenaText: right])
    #expect(LeaderboardPresentation.rankingUpdated(snapshot, category: .general, language: .chinese, now: now) == "榜单 1 小时前")
    #expect(LeaderboardPresentation.rankingUpdated(snapshot, category: .image, language: .english, now: now) == "Rankings pending")
    #expect(LeaderboardPresentation.updateAge(now.addingTimeInterval(-59), language: .english, now: now) == "just now")
    #expect(LeaderboardPresentation.updateAge(now.addingTimeInterval(-60), language: .chinese, now: now) == "1 分钟前")
    #expect(LeaderboardPresentation.updateAge(now.addingTimeInterval(-86_400), language: .english, now: now) == "1 day ago")
}
