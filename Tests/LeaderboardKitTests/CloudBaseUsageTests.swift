import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LeaderboardKit

@Test func cloudBaseSharesRemainDistinctFromVolumesAndPreservePreferences() throws {
    #expect(LeaderboardCategory.usage.boardKinds == [.openRouterUsage, .vercelUsage, .cloudbaseUsage])
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

private final class CloudBaseSharedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let allowed = request.url?.host == "cloudbase-fixture.invalid"
            && request.url?.path.hasPrefix("/v1/boards/cloudbaseUsage") == true
        let response = HTTPURLResponse(url: request.url!, statusCode: allowed ? 200 : 403,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"board":{"kind":"cloudbaseUsage","title":"Tencent CloudBase","fetchedAt":"2026-10-24T00:00:00Z","entries":[{"rank":1,"name":"Kimi K3","score":1.1}]}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func restoredCloudBaseReadsSharedDataAndRetainsSourceSelectionWithoutOriginFallback() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CloudBaseSharedProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let fetcher = LeaderboardFetcher(session: session, sharedEndpoint: URL(string: "https://cloudbase-fixture.invalid")!)
    let board = try await fetcher.fetch(.cloudbaseUsage)
    #expect(board.entries.first?.name == "Kimi K3")
    #expect(board.entries.first?.score == 1.1)
    #expect(try await fetcher.fetchCached(.cloudbaseUsage)?.kind == .cloudbaseUsage)
    #expect(DesktopBoardSelection.kinds(for: .usage, saved: ["cloudbaseUsage"]) == [.cloudbaseUsage])
    do {
        _ = try await LeaderboardFetcher(session: session, sharedEndpoint: nil).fetch(.cloudbaseUsage)
        Issue.record("CloudBase must use the shared service")
    } catch let error as URLError { #expect(error.code == .resourceUnavailable) }
}
