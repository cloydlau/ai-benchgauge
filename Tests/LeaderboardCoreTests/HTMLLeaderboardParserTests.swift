import Foundation
import LeaderboardCore
import Testing

struct HTMLLeaderboardParserTests {
    @Test
    func testParsesArtificialAnalysisTopTwenty() throws {
        let records = (1...22).map { index in
            #"{"slug":"model-\#(index)","name":"Model \#(index)","deprecated":false,"creator":{"name":"Maker","logo":"/img/logos/maker.svg"},"intelligenceIndex":\#(100-index),"intelligenceIndexIsEstimated":false}"#
        }
        let html = rscHTML(
            payload: "[\(records.joined(separator: ","))]",
            title: "Artificial Analysis Intelligence Index v4.3.2 | Artificial Analysis"
        )

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)

        #expect((leaderboard.sourceNote) == ("v4.3.2"))
        #expect((leaderboard.sourceUpdatedAt) == nil)
        #expect((leaderboard.entries.count) == (20))
        #expect((leaderboard.entries.first?.name) == ("Model 1"))
        #expect((leaderboard.entries.first?.score) == (99))
        #expect((leaderboard.entries.first?.modelID) == ("model-1"))
        #expect((leaderboard.entries.first?.organization) == ("Maker"))
        #expect((leaderboard.entries.first?.logoURL?.absoluteString) == ("https://artificialanalysis.ai/img/logos/maker.svg"))
        #expect((leaderboard.organizationLogoURLs?["Maker"]?.absoluteString) == ("https://artificialanalysis.ai/img/logos/maker.svg"))
        #expect((leaderboard.entries.last?.name) == ("Model 20"))
    }

    @Test
    func testParsesArtificialAnalysisCodingAgentIndex() throws {
        let records = (1...12).map { index in
            #"{"displayLabel":"Agent \#(index) - Model \#(index)","hostModelSlug":"model-\#(index)","display":{"creator":{"agent":"Maker"}},"indexScore":\#(Double(100 - index) / 100)}"#
        }
        let html = rscHTML(
            payload: "[\(records.joined(separator: ","))]",
            title: "Artificial Analysis Coding Agent Index v1.5"
        )

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: html)

        #expect((leaderboard.kind) == (.artificialAnalysisCodingAgent))
        #expect((leaderboard.entries.count) == (12))
        #expect((leaderboard.entries.first?.name) == ("Agent 1 - Model 1"))
        #expect((leaderboard.entries.first?.score) == (99))
        #expect((leaderboard.entries.first?.modelID) == ("model-1"))
        #expect((leaderboard.entries.first?.organization) == ("Maker"))
        #expect((leaderboard.sourceNote) == ("v1.5"))
        #expect((leaderboard.sourceUpdatedAt) == nil)
    }

    @Test
    func testParsesArenaTopTwentyAndCutoff() throws {
        let records = (1...22).map { index in
            #"{"rank":\#(index),"modelKey":"arena-model-\#(index)","modelDisplayName":"Arena Model \#(index)","modelOrganization":"Maker","rating":\#(2000-index)}"#
        }
        let html = rscHTML(
            payload: #"{"leaderboard":{"entries":[\#(records.joined(separator: ","))],"voteCutoffISOString":"2026-09-11T19:00:00.000Z"}}"#
        )

        let leaderboard = try HTMLLeaderboardParser.arenaWebDev(fromHTML: html)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try #require(formatter.date(from: "2026-09-11T19:00:00.000Z"))

        #expect((leaderboard.sourceUpdatedAt) == (expected))
        #expect((leaderboard.entries.count) == (20))
        #expect((leaderboard.entries.first?.name) == ("Arena Model 1"))
        #expect((leaderboard.entries.first?.score) == (1999))
        #expect((leaderboard.entries.first?.modelID) == ("arena-model-1"))
        #expect((leaderboard.entries.first?.organization) == ("Maker"))
    }

    @Test
    func testParsesArenaTextToImageWithSharedParser() throws {
        let records = (1...22).map { index in
            #"{"rank":\#(index),"modelKey":"image-model-\#(index)","modelDisplayName":"Image Model \#(index)","modelOrganization":"Maker","rating":\#(1300-index)}"#
        }
        let html = rscHTML(
            payload: #"{"leaderboard":{"entries":[\#(records.joined(separator: ","))],"voteCutoffISOString":"2026-09-07T22:00:00.000Z"}}"#
        )

        let leaderboard = try HTMLLeaderboardParser.arenaTextToImage(fromHTML: html)

        #expect((leaderboard.kind) == (.arenaTextToImage))
        #expect((leaderboard.title) == ("Arena | 文生图"))
        #expect((leaderboard.entries.count) == (20))
        #expect((leaderboard.entries.first?.name) == ("Image Model 1"))
        #expect((leaderboard.entries.first?.score) == (1299))
    }

    @Test
    func testParsesArtificialAnalysisMediaBoardAndKeepsPrimaryOccurrence() throws {
        let primary = (1...22).map { index in
            #"{"formatted":{"rank":\#(index)},"values":{"id":"image-\#(index)","name":"Image Model \#(index)","elo":\#(1200-index),"creator":{"name":"Maker","logo":"/img/logos/maker.svg"}}}"#
        }
        let duplicate = #"{"formatted":{"rank":1},"values":{"id":"image-1","name":"Image Model 1","elo":9999,"creator":{"name":"Maker","logo":"/img/logos/maker.svg"}}}"#
        let html = rscHTML(
            payload: "[\(primary.joined(separator: ",")),\(duplicate)]",
            title: "Text to Image Leaderboard - Top AI Image Models | Artificial Analysis"
        )

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: html)

        #expect((leaderboard.kind) == (.artificialAnalysisTextToImage))
        #expect((leaderboard.title) == ("Artificial Analysis | 文生图"))
        #expect((leaderboard.sourceUpdatedAt) == nil)
        #expect((leaderboard.entries.count) == (20))
        #expect((leaderboard.entries.first?.name) == ("Image Model 1"))
        #expect((leaderboard.entries.first?.score) == (1199))
        #expect((leaderboard.entries.first?.logoURL?.absoluteString) == ("https://artificialanalysis.ai/img/logos/maker.svg"))
    }

    @Test
    func testParsesArtificialAnalysisDataTimestamp() throws {
        let records = (1...22).map { index in
            #"{"slug":"model-\#(index)","name":"Model \#(index)","creator":{"name":"Maker"},"intelligenceIndex":\#(100-index),"intelligenceIndexIsEstimated":false,"grading":{"materializedAt":"2026-09-23T06:01:07.399143+00:00"}}"#
        }
        let html = rscHTML(payload: "[\(records.joined(separator: ","))]")

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)

        #expect((leaderboard.sourceUpdatedAt) == (try expectedDate("2026-09-23T06:01:07.399Z")))
    }

    @Test
    func testParsesNewestArtificialAnalysisCodingAgentTimestamp() throws {
        let stale = "2026-09-20T01:02:03.123456+00:00"
        let newest = "2026-09-23T06:01:07.399143+00:00"
        let records = (1...12).map { index -> String in
            let stamp = index == 7 ? newest : stale
            return #"{"displayLabel":"Agent \#(index)","hostModelSlug":"model-\#(index)","display":{"creator":{"agent":"Maker"}},"indexScore":0.5,"grading":{"materializedAt":"\#(stamp)"}}"#
        }
        let html = rscHTML(payload: "[\(records.joined(separator: ","))]")

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: html)

        #expect((leaderboard.sourceUpdatedAt) == (try expectedDate("2026-09-23T06:01:07.399Z")))
    }

    @Test
    func testParsesArtificialAnalysisMediaBoardDataTimestamp() throws {
        let records = (1...22).map { index in
            #"{"formatted":{"rank":\#(index)},"values":{"id":"image-\#(index)","name":"Image Model \#(index)","elo":\#(1200-index),"creator":{"name":"Maker"}},"grading":{"materializedAt":"2026-09-22T08:09:10.111222+00:00"}}"#
        }
        let html = rscHTML(payload: "[\(records.joined(separator: ","))]")

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysisTextToImage(fromHTML: html)

        #expect((leaderboard.sourceUpdatedAt) == (try expectedDate("2026-09-22T08:09:10.111Z")))
        #expect((leaderboard.entries.count) == (20))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: savedLeaderboardFixtureURL("artificial-analysis.html")), "Optional saved HTML snapshot"))
    func testParsesSavedArtificialAnalysisPage() throws {
        let path = fixtureURL("artificial-analysis.html")
        try #require(FileManager.default.fileExists(atPath: path))
        let html = try String(contentsOfFile: path, encoding: .utf8)

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)

        #expect((leaderboard.entries.count) == (20))
        #expect(leaderboard.entries.first!.score > leaderboard.entries.last!.score)
        #expect((leaderboard.sourceNote) != nil)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: savedLeaderboardFixtureURL("arena-webdev.html")), "Optional saved HTML snapshot"))
    func testParsesSavedArenaPage() throws {
        let path = fixtureURL("arena-webdev.html")
        try #require(FileManager.default.fileExists(atPath: path))
        let html = try String(contentsOfFile: path, encoding: .utf8)

        let leaderboard = try HTMLLeaderboardParser.arenaWebDev(fromHTML: html)

        #expect((leaderboard.entries.count) == (20))
        #expect(leaderboard.entries.first!.score > leaderboard.entries.last!.score)
        #expect((leaderboard.sourceUpdatedAt) != nil)
    }

    private func fixtureURL(_ fileName: String) -> String {
        savedLeaderboardFixtureURL(fileName)
    }

    private func rscHTML(payload: String, title: String? = nil) -> String {
        let escaped = payload
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let titleTag = title.map { "<title>\($0)</title>" } ?? ""
        return #"<html>\#(titleTag)<script>self.__next_f.push([1,"\#(escaped)"])</script></html>"#
    }

    private func expectedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(formatter.date(from: value))
    }
}

private func savedLeaderboardFixtureURL(_ fileName: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "work", directoryHint: .isDirectory)
        .appending(path: fileName)
        .path
}
