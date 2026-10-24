import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import LeaderboardKit

@Test func arenaDatasetMigrationPreservesProvenanceAndAcceptsPublicationDatesWithoutFabricatedTimes() throws {
    let fetched = Date(timeIntervalSince1970: 1_792_368_000)
    let entry = LeaderboardEntry(rank: 1, name: "Fixture", score: 1523.9035861299108)
    let board = Leaderboard(kind: .arenaText, title: "Fixture", sourceUpdatedAt: fetched.addingTimeInterval(-4 * 86400),
        sourceNote: ArenaAttribution.sourceURL + "/tree/" + String(repeating: "a", count: 40), fetchedAt: fetched, entries: [entry])
    let old = Leaderboard(kind: .arenaText, title: "Website", sourceUpdatedAt: fetched.addingTimeInterval(-1),
        fetchedAt: fetched.addingTimeInterval(-1), entries: [entry])
    #expect(board.canReplace(old))
    #expect(!old.canReplace(board))
    #expect(try JSONDecoder().decode(Leaderboard.self, from: JSONEncoder().encode(board)) == board)
    for language in AppLanguage.allCases {
        let notice = ArenaAttribution.fullText(language: language)
        #expect(notice.contains("Arena · Arena Leaderboard Dataset · CC BY 4.0"))
        #expect(notice.contains(ArenaAttribution.sourceURL))
        #expect(notice.contains(ArenaAttribution.licenseURL))
        #expect(ArenaAttribution.applies(board))
        #expect(!ArenaAttribution.applies(old))
        let source = LeaderboardPresentation.sourceTime(board, language: language, timeZone: TimeZone(secondsFromGMT: -28800)!)
        #expect(source.isSourceTime)
        #expect(source.text == "2026-10-15 \(language.text("Published", "发布"))")
        let mobile = LeaderboardPresentation.sourceTime(board, language: language,
            timeZone: TimeZone(secondsFromGMT: -28800)!, includesYear: false)
        #expect(mobile.text == "10-15 \(language.text("Published", "发布"))")
        #expect(mobile.isSourceTime)
        #expect(!source.text.contains(":"))
        #expect(!source.text.contains(language.text("Fetched", "抓取")))
    }
}

@Test func arenaWithoutSharedServiceNeverFallsBackToWebsiteScraping() async {
    let fetcher = LeaderboardFetcher(sharedEndpoint: nil)
    for kind in [LeaderboardKind.arenaText, .codeArenaWebDev, .arenaTextToImage, .arenaTextToVideo] {
        await #expect(throws: URLError(.resourceUnavailable)) { try await fetcher.fetch(kind) }
    }
}
