import Foundation
import Testing
import LeaderboardKit

private func board(_ kind: LeaderboardKind, score: Double = 90, fetchedAt: Date = Date()) -> Leaderboard {
    Leaderboard(kind: kind, title: "Fixture", fetchedAt: fetchedAt, entries: [
        LeaderboardEntry(rank: 1, name: "GPT", score: score, organization: "OpenAI"),
        LeaderboardEntry(rank: 2, name: "DeepSeek", score: score - 1, organization: "DeepSeek"),
    ])
}

@Test func partialRefreshPreservesOfflineAndOtherCategories() async {
    let cached = board(.arenaText, score: 80)
    let image = board(.arenaTextToImage)
    let service = LeaderboardService { kind in
        if kind == .arenaText { throw URLError(.notConnectedToInternet) }
        return board(kind)
    }
    let result = await service.refresh(LeaderboardCategory.general.boardKinds,
        keeping: LeaderboardSnapshot(boards: [.arenaText: cached, .arenaTextToImage: image]))
    #expect(result.snapshot.boards[.arenaText] == cached)
    #expect(result.snapshot.boards[.arenaTextToImage] == image)
    #expect(result.snapshot.boards[.artificialAnalysis]?.entries.first?.score == 90)
    #expect(result.failures == [.arenaText: .offline])
}

@Test func invalidSourceResultNeverPoisonsCache() async {
    let cached = board(.arenaText)
    let service = LeaderboardService { _ in board(.artificialAnalysis) }
    let result = await service.refresh([.arenaText], keeping: LeaderboardSnapshot(boards: [.arenaText: cached]))
    #expect(result.snapshot.boards[.arenaText] == cached)
    #expect(result.failures == [.arenaText: .sourceUnavailable])
    let empty = LeaderboardService { Leaderboard(kind: $0, title: "Empty", entries: []) }
    let emptyResult = await empty.refresh([.arenaText], keeping: LeaderboardSnapshot(boards: [.arenaText: cached]))
    #expect(emptyResult.snapshot.boards[.arenaText] == cached)
    #expect(emptyResult.failures[.arenaText] == .sourceUnavailable)
}

@Test func foregroundFreshnessAndRetryBackoff() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let kinds = LeaderboardCategory.general.boardKinds
    let snapshot = LeaderboardSnapshot(boards: [.arenaText: board(.arenaText, fetchedAt: now.addingTimeInterval(-86_400))])
    #expect(LeaderboardFreshness.dueKinds(kinds, snapshot: snapshot, lastAttempts: [:], now: now) == kinds)
    #expect(LeaderboardFreshness.dueKinds(kinds, snapshot: snapshot, lastAttempts: [.arenaText: now], now: now) == [.artificialAnalysis])
    #expect(LeaderboardFreshness.dueKinds([.arenaText], snapshot: snapshot,
        lastAttempts: [.arenaText: now.addingTimeInterval(-300)], now: now) == [.arenaText])
    let fresh = LeaderboardSnapshot(boards: [.arenaText: board(.arenaText, fetchedAt: now.addingTimeInterval(-60))])
    #expect(LeaderboardFreshness.dueKinds([.arenaText], snapshot: fresh, lastAttempts: [:], now: now).isEmpty)
}

@Test func countryFilterPreservesSourceRanksAndCompanyScores() {
    let source = board(.arenaText)
    let china = LeaderboardPresentation.rows(source, grouping: .model, country: .china)
    #expect(china.count == 1)
    #expect(china.first?.rank == 2)
    #expect(LeaderboardPresentation.rows(source, grouping: .company, country: .unitedStates).first?.score == 90)
    #expect(LeaderboardPresentation.countries(source, grouping: .model) == [.china, .unitedStates])
    #expect(LeaderboardCategory.allCases.flatMap(\.boardKinds).count == LeaderboardKind.allCases.count)
}

@Test func cacheRoundTripUsesPortableLibrary() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = LeaderboardCache(fileURL: directory.appending(path: "leaderboards.json"))
    let snapshot = LeaderboardSnapshot(boards: [.arenaText: board(.arenaText, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))])
    cache.save(snapshot)
    #expect(cache.load() == snapshot)
}
