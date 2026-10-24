import Foundation
import Testing
@testable import LeaderboardKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Test func usageIsAnIndependentCategoryAndPreservesExactCounts() throws {
    #expect(LeaderboardCategory.usage.boardKinds == [.openRouterUsage, .vercelUsage, .cloudbaseUsage])
    #expect(LeaderboardKind.openRouterUsage.sourceURL.absoluteString == "https://openrouter.ai/rankings")
    #expect(LeaderboardKind.openRouterUsage.sourcePrefix == "OpenRouter")
    let entries = [
        LeaderboardEntry(rank: 1, name: "openai/model-a", score: 5, modelID: "openai/model-a", organization: "OpenAI", totalTokens: "5000000000"),
        LeaderboardEntry(rank: 2, name: "anthropic/model-b", score: 4, organization: "Anthropic", totalTokens: "4000000000"),
        LeaderboardEntry(rank: 3, name: "openai/model-c:free", score: 3, organization: "OpenAI", totalTokens: "3000000000")]
    let board = Leaderboard(kind: .openRouterUsage, title: "OpenRouter", sourceNote: "Source: OpenRouter (openrouter.ai/rankings), as of 2026-10-23T00:00:30Z.\nLicensed under CC BY 4.0.\nUTC 2026-10-22", entries: entries)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let snapshot = LeaderboardSnapshot(boards: [.openRouterUsage: board])
    let decoded = try decoder.decode(LeaderboardSnapshot.self, from: encoder.encode(snapshot))
    #expect(decoded.boards[.openRouterUsage]?.entries.first?.totalTokens == "5000000000")
    #expect(decoded.boards[.openRouterUsage]?.sourceNote == board.sourceNote)
    #expect(LeaderboardPresentation.rows(board, grouping: .company).map(\.score) == [8, 4])
    let companies = LeaderboardPresentation.companies(board, filter: .all)
    #expect(companies.first?.entry.totalTokens == "8000000000")
    #expect(CompanyLeaderboard.rank(entries).map(\.entry.score) == [5, 4])
    #expect(CompanyLeaderboard.scoreHelp(for: companies[0], language: .english).contains("Sum of listed models only"))
    #expect(!CompanyLeaderboard.scoreHelp(for: companies[0], language: .chinese).contains("最强"))
    for language in AppLanguage.allCases {
        #expect(!LeaderboardPresentation.scoreTitle(.openRouterUsage, language: language).isEmpty)
        #expect(!LeaderboardPresentation.title(.usage, language: language).isEmpty)
        #expect(LeaderboardPresentation.sourceHelp(.openRouterUsage, language: language, board: board).contains("1B"))
    }
    #expect(LeaderboardPresentation.scoreText(5.678, kind: .openRouterUsage) == "5.68B")
    #expect(LeaderboardPresentation.scoreText(0.0001, kind: .openRouterUsage) == "<0.01B")
    #expect(LeaderboardPresentation.scoreText(0, kind: .openRouterUsage) == "0.00B")
    #expect(LeaderboardPresentation.scoreText(12.346, kind: .epochECI) == "12.35")
    #expect(LeaderboardPresentation.scoreText(12.345, kind: .arenaText) == "12.3")
    #expect(LeaderboardPresentation.scoreTitle(.arenaText, language: .english) == "Score")
}

@Test func usageCompanyTotalsPreserveExactCountsWithMissingOrMalformedLegacyValues() throws {
    let entries = [
        LeaderboardEntry(rank: 1, name: "Exact", score: 9, organization: "OpenAI", totalTokens: "9007199254740993"),
        LeaderboardEntry(rank: 2, name: "Missing", score: 2, organization: "OpenAI"),
        LeaderboardEntry(rank: 3, name: "Malformed", score: 1, organization: "OpenAI", totalTokens: "invalid")
    ]
    let company = try #require(CompanyLeaderboard.rank(entries, summingUsage: true).first)
    #expect(company.entry.totalTokens == "9007199254740993")
    #expect(company.entry.score == 12)
    #expect(company.components.count == 3)
    #expect(CompanyLeaderboard.rank(entries).first?.entry.totalTokens == nil)
}

private final class UsageConfigurationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Any direct OpenRouter fetch would fail, rather than silently scrape.
        let allowed = request.url?.host == "usage-fixture.invalid"
        let response = HTTPURLResponse(url: request.url!, statusCode: allowed ? 200 : 403, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"board":null,"configurationRequired":true}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@Test func missingUsageKeyIsAnExplicitConfigurationStateWithoutOriginFallback() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageConfigurationProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let fetcher = LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://usage-fixture.invalid"))
    await #expect(throws: LeaderboardConfigurationRequired.self) { try await fetcher.fetch(.openRouterUsage) }
    await #expect(throws: LeaderboardConfigurationRequired.self) { try await fetcher.fetchCached(.openRouterUsage) }
    let direct = LeaderboardFetcher(session: session, sharedEndpoint: nil)
    await #expect(throws: LeaderboardConfigurationRequired.self) { try await direct.fetch(.openRouterUsage) }
    #expect(throws: URLError.self) { try direct.parse(.openRouterUsage, html: "<html>not an API dataset</html>") }
    let result = await LeaderboardService(fetcher: fetcher).refresh([.openRouterUsage], keeping: .init())
    #expect(result.failures[.openRouterUsage] == .configurationRequired)
    #expect(result.snapshot.boards.isEmpty)
    #expect(LeaderboardFailure.configurationRequired.message(language: .chinese, hasCachedBoard: false).contains("数据源待配置"))
}
