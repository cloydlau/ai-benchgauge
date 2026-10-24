import Foundation
import Testing
@testable import LeaderboardKit

@Test func vercelSharesStaySeparateFromAbsoluteTokenTotals() throws {
    #expect(LeaderboardCategory.usage.boardKinds == [.openRouterUsage, .vercelUsage, .cloudbaseUsage])
    #expect(LeaderboardKind.vercelUsage.sourceURL.host == "vercel.com")
    let board = Leaderboard(kind: .vercelUsage, title: "Vercel AI Gateway", entries: [
        LeaderboardEntry(rank: 1, name: "Model One", score: 30, organization: "OpenAI"),
        LeaderboardEntry(rank: 2, name: "Model Two", score: 20, organization: "OpenAI"),
        LeaderboardEntry(rank: 3, name: "Model Three", score: 0.0001, organization: "Anthropic")])
    let companies = LeaderboardPresentation.companies(board, filter: .all)
    #expect(companies[0].entry.score == 50)
    #expect(companies[0].entry.totalTokens == nil)
    #expect(LeaderboardPresentation.scoreText(30.123, kind: .vercelUsage) == "30.12%")
    #expect(LeaderboardPresentation.scoreText(0.0001, kind: .vercelUsage) == "<0.01%")
    #expect(LeaderboardPresentation.scoreText(0, kind: .vercelUsage) == "0.00%")
    let help = CompanyLeaderboard.scoreHelp(for: companies[0], language: .english, kind: .vercelUsage)
    #expect(help.contains("Sum of listed model shares"))
    #expect(help.contains("30.00%"))
    #expect(!help.contains("strongest"))
    // A source kind remains authoritative for older caches without token strings.
    #expect(CompanyLeaderboard.scoreHelp(for: companies[0], language: .english, kind: .openRouterUsage).contains("Sum of listed models only"))
    let decoded = try JSONDecoder().decode(LeaderboardKind.self, from: Data("\"vercelUsage\"".utf8))
    #expect(decoded == .vercelUsage)
    for language in AppLanguage.allCases {
        #expect(!LeaderboardPresentation.scoreTitle(.vercelUsage, language: language).isEmpty)
        #expect(!LeaderboardPresentation.title(.vercelUsage, language: language).isEmpty)
        #expect(LeaderboardPresentation.sourceHelp(.vercelUsage, language: language, board: board).contains("OpenRouter"))
        let license = CCBYLicense.vercelText(sourceNote: nil, language: language)
        #expect(license.contains("© 2026 Vercel"))
        #expect(license.contains(CCBYLicense.canonicalURL))
        #expect(CCBYLicense.vercelText(sourceNote: "Cached Vercel UTC day", language: language).hasPrefix("Cached Vercel UTC day\n\n"))
        #expect(CCBYLicense.vercelText(sourceNote: "   ", language: language).contains("AI Gateway Leaderboard Data"))
    }
}

@Test func vercelShowsItsUTCStatisticDayWithoutInventingAPublicationTime() {
    let day = ISO8601DateFormatter().date(from: "2026-10-22T00:00:00Z")!
    let board = Leaderboard(kind: .vercelUsage, title: "Vercel AI Gateway", sourceUpdatedAt: day, entries: [])
    let labels = LeaderboardPresentation.sourceTime(board, language: .english, timeZone: TimeZone(secondsFromGMT: -10 * 3600)!)
    #expect(labels.text == "10/22 UTC day")
    #expect(labels.isSourceTime)
    #expect(LeaderboardPresentation.sourceTimeHelp(board, language: .english) == "2026-10-22 UTC day")
    #expect(!labels.text.contains("Published"))
    let unknown = Leaderboard(kind: .vercelUsage, title: "Vercel", entries: [])
    #expect(!LeaderboardPresentation.sourceTime(unknown, language: .chinese).isSourceTime)
    #expect(LeaderboardPresentation.sourceTimeHelp(unknown, language: .chinese).hasSuffix("刷新"))
}
