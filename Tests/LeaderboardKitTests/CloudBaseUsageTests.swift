import Foundation
import Testing
@testable import LeaderboardKit

@Test func cloudBaseSharesRemainDistinctFromVolumesAndPreservePreferences() throws {
    #expect(LeaderboardCategory.usage.boardKinds == [.openRouterUsage, .vercelUsage])
    #expect(LeaderboardKind.cloudbaseUsage.sourceURL.host == "docs.cloudbase.net")
    let board = Leaderboard(kind: .cloudbaseUsage, title: "Tencent CloudBase", entries: [
        .init(rank: 1, name: "GLM 5.3", score: 20, organization: "zai"),
        .init(rank: 2, name: "GLM 5.3 Flash", score: 10, organization: "zai")
    ])
    let company = try #require(LeaderboardPresentation.companies(board, filter: .all).first)
    #expect(company.entry.score == 30)
    #expect(company.entry.totalTokens == nil)
    #expect(LeaderboardPresentation.scoreText(company.entry.score, kind: .cloudbaseUsage) == "30.00%")
    #expect(CompanyLeaderboard.scoreHelp(for: company, language: .english, kind: .cloudbaseUsage).contains("20.00%"))
    #expect(LeaderboardPresentation.sourceTime(board, language: .chinese).text == "抽样统计")
    #expect(LeaderboardPresentation.sourceTimeHelp(board, language: .english).contains("does not publish full sample dates"))
    #expect(try JSONDecoder().decode(LeaderboardKind.self, from: Data("\"cloudbaseUsage\"".utf8)) == .cloudbaseUsage)
    for language in AppLanguage.allCases {
        #expect(!LeaderboardPresentation.sourceSummary(.cloudbaseUsage, language: language).isEmpty)
        #expect(!LeaderboardPresentation.title(.cloudbaseUsage, language: language).isEmpty)
        let notice = CloudBaseAttribution.text(sourceNote: "cached Tencent provenance", language: language)
        #expect(notice.contains("cached Tencent provenance"))
        #expect(!notice.contains("creativecommons.org/licenses"))
        let fallback = CloudBaseAttribution.text(sourceNote: nil, language: language)
        #expect(fallback.contains("https://docs.cloudbase.net/ai/announcement/model-token-volume"))
        #expect(!fallback.contains("creativecommons.org/licenses"))
        #expect(CloudBaseAttribution.text(sourceNote: "", language: language) == fallback)
    }
}

@Test func disabledCloudBaseDoesNotRequestSharedOrUpstreamData() async throws {
    let fetcher = LeaderboardFetcher(sharedEndpoint: URL(string: "http://127.0.0.1:1")!)
    do {
        _ = try await fetcher.fetch(.cloudbaseUsage)
        Issue.record("Disabled source must not fetch")
    } catch let error as URLError {
        #expect(error.code == .resourceUnavailable)
    }
    #expect(try await fetcher.fetchCached(.cloudbaseUsage) == nil)
    #expect(DesktopBoardSelection.kinds(for: .usage, saved: ["cloudbaseUsage"]) == [.openRouterUsage, .vercelUsage])
}
