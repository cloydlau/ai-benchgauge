import Foundation
import Testing
@testable import LeaderboardKit

struct ParserBoundaryTests {
    private func page(_ values: [[String: Any]]) throws -> String {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        let escaped = String(decoding: try JSONSerialization.data(withJSONObject: [json]), as: UTF8.self).dropFirst().dropLast()
        return "<title>Fixture without version</title><script>self.__next_f.push([1,\(escaped)])</script>"
    }
    @Test func eachSourceDeduplicatesRecordsAndOrdersEqualScoresByName() throws {
        let basic = (0..<20).map { ["name": String(format: "M%02d", $0), "intelligenceIndex": 50, "creator": ["logo": "https://example.invalid/logo.png"]] as [String: Any] }
        var rows = basic + [basic[0], ["name": "estimated", "intelligenceIndex": 99, "intelligenceIndexIsEstimated": true], ["intelligenceIndex": 99]]
        #expect(try HTMLLeaderboardParser.artificialAnalysis(fromHTML: page(rows)).entries.map(\.name) == basic.map { $0["name"] as! String })
        #expect(throws: (any Error).self) { try HTMLLeaderboardParser.artificialAnalysis(fromHTML: page([])) }
        rows = (0..<20).map { ["formatted": [:], "values": ["name": String(format: "M%02d", $0), "elo": 50]] as [String: Any] }
        rows.append(["formatted": [:], "values": ["name": "missing score"]])
        #expect(try HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: page(rows)).entries.first?.name == "M00")
        #expect(throws: (any Error).self) { try HTMLLeaderboardParser.artificialAnalysisTextToVideo(fromHTML: page([])) }
        rows = (0..<20).map { ["modelDisplayName": String(format: "M%02d", $0), "rating": 50] as [String: Any] }
        rows.append(rows[0])
        #expect(try HTMLLeaderboardParser.arenaText(fromHTML: page(rows)).entries.first?.name == "M00")
        #expect(throws: (any Error).self) { try HTMLLeaderboardParser.arenaTextToVideo(fromHTML: page([])) }
        rows = (0..<10).map { ["displayLabel": "Agent \($0)", "indexScore": 0.5] as [String: Any] }
        rows += [rows[0], ["indexScore": 0.9]]
        #expect(try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: page(rows)).entries.count == 10)
        #expect(throws: (any Error).self) { try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: page([])) }
    }
    @Test func escapedAndTruncatedPayloadsDoNotCrashOrInventDates() {
        #expect(HTMLLeaderboardParser.rscPayload(in: #"self.__next_f.push([1,"unterminated"#) == "")
        #expect(HTMLLeaderboardParser.unescapedRSCJSON(#"a\nb\rc\td\q"#) == "a\nb\rc\td\\q")
        #expect(HTMLLeaderboardParser.artificialAnalysisLogoURL(from: "https://example.invalid/logo")?.host == "example.invalid")
        #expect(HTMLLeaderboardParser.artificialAnalysisVersion(fromHTML: "<title>No version</title>") == nil)
        #expect(HTMLLeaderboardParser.jsonStringValues(in: "materializedAt: unterminated", afterKey: "materializedAt").isEmpty)
        #expect(HTMLLeaderboardParser.iso8601Date("2026-10-13T00:00:00.000Z") != nil)
        #expect(HTMLLeaderboardParser.iso8601Date("2026-10-13T00:00:00Z") != nil)
        #expect(HTMLLeaderboardParser.iso8601Date("invalid date") == nil)
        #expect(OrganizationLogoCatalog.resolvedKey(organization: "Unknown", modelName: "Harness - Mystery") == nil)
        #expect(HTMLLeaderboardParser.jsonObjects(in: #"self.__next_f.push([1,"{\"name\":\"a\\\"b\",\"marker\":1}"])"#, containing: "marker").isEmpty)
    }
}


extension ParserBoundaryTests {
    @Test func sharedAndStandaloneFreshnessIntervalsRemainDistinct() {
        #expect(LeaderboardFreshness.interval(sharedEndpoint: nil) == 86400)
        #expect(LeaderboardFreshness.interval(sharedEndpoint: URL(string: "https://fixture.invalid")) == 1800)
    }
}
