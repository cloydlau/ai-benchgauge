import LeaderboardCore
import XCTest

final class HTMLLeaderboardParserTests: XCTestCase {
    func testParsesArtificialAnalysisTopTwenty() throws {
        let records = (1...22).map { index in
            #"{"slug":"model-\#(index)","name":"Model \#(index)","deprecated":false,"creator":{"name":"Maker","logo":"/img/logos/maker.svg"},"intelligenceIndex":\#(100-index),"intelligenceIndexIsEstimated":false}"#
        }
        let html = rscHTML(
            payload: "[\(records.joined(separator: ","))]",
            title: "Artificial Analysis Intelligence Index v4.3.2 | Artificial Analysis"
        )

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)

        XCTAssertEqual(leaderboard.sourceNote, "v4.3.2")
        XCTAssertNil(leaderboard.sourceUpdatedAt)
        XCTAssertEqual(leaderboard.entries.count, 20)
        XCTAssertEqual(leaderboard.entries.first?.name, "Model 1")
        XCTAssertEqual(leaderboard.entries.first?.score, 99)
        XCTAssertEqual(leaderboard.entries.first?.modelID, "model-1")
        XCTAssertEqual(leaderboard.entries.first?.organization, "Maker")
        XCTAssertEqual(
            leaderboard.entries.first?.logoURL?.absoluteString,
            "https://artificialanalysis.ai/img/logos/maker.svg"
        )
        XCTAssertEqual(leaderboard.organizationLogoURLs?["Maker"]?.absoluteString,
                       "https://artificialanalysis.ai/img/logos/maker.svg")
        XCTAssertEqual(leaderboard.entries.last?.name, "Model 20")
    }

    func testParsesArtificialAnalysisCodingAgentIndex() throws {
        let records = (1...12).map { index in
            #"{"displayLabel":"Agent \#(index) - Model \#(index)","hostModelSlug":"model-\#(index)","display":{"creator":{"agent":"Maker"}},"indexScore":\#(Double(100 - index) / 100)}"#
        }
        let html = rscHTML(
            payload: "[\(records.joined(separator: ","))]",
            title: "Artificial Analysis Coding Agent Index v1.5"
        )

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysisCodingAgent(fromHTML: html)

        XCTAssertEqual(leaderboard.kind, .artificialAnalysisCodingAgent)
        XCTAssertEqual(leaderboard.entries.count, 12)
        XCTAssertEqual(leaderboard.entries.first?.name, "Agent 1 - Model 1")
        XCTAssertEqual(leaderboard.entries.first?.score, 99)
        XCTAssertEqual(leaderboard.entries.first?.modelID, "model-1")
        XCTAssertEqual(leaderboard.entries.first?.organization, "Maker")
        XCTAssertEqual(leaderboard.sourceNote, "v1.5")
        XCTAssertNil(leaderboard.sourceUpdatedAt)
    }

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
        let expected = try XCTUnwrap(formatter.date(from: "2026-09-11T19:00:00.000Z"))

        XCTAssertEqual(leaderboard.sourceUpdatedAt, expected)
        XCTAssertEqual(leaderboard.entries.count, 20)
        XCTAssertEqual(leaderboard.entries.first?.name, "Arena Model 1")
        XCTAssertEqual(leaderboard.entries.first?.score, 1999)
        XCTAssertEqual(leaderboard.entries.first?.modelID, "arena-model-1")
        XCTAssertEqual(leaderboard.entries.first?.organization, "Maker")
    }

    func testParsesArenaTextToImageWithSharedParser() throws {
        let records = (1...22).map { index in
            #"{"rank":\#(index),"modelKey":"image-model-\#(index)","modelDisplayName":"Image Model \#(index)","modelOrganization":"Maker","rating":\#(1300-index)}"#
        }
        let html = rscHTML(
            payload: #"{"leaderboard":{"entries":[\#(records.joined(separator: ","))],"voteCutoffISOString":"2026-09-07T22:00:00.000Z"}}"#
        )

        let leaderboard = try HTMLLeaderboardParser.arenaTextToImage(fromHTML: html)

        XCTAssertEqual(leaderboard.kind, .arenaTextToImage)
        XCTAssertEqual(leaderboard.title, "Arena | 文生图")
        XCTAssertEqual(leaderboard.entries.count, 20)
        XCTAssertEqual(leaderboard.entries.first?.name, "Image Model 1")
        XCTAssertEqual(leaderboard.entries.first?.score, 1299)
    }

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

        XCTAssertEqual(leaderboard.kind, .artificialAnalysisTextToImage)
        XCTAssertEqual(leaderboard.title, "Artificial Analysis | 文生图")
        XCTAssertNil(leaderboard.sourceUpdatedAt)
        XCTAssertEqual(leaderboard.entries.count, 20)
        XCTAssertEqual(leaderboard.entries.first?.name, "Image Model 1")
        XCTAssertEqual(leaderboard.entries.first?.score, 1199)
        XCTAssertEqual(
            leaderboard.entries.first?.logoURL?.absoluteString,
            "https://artificialanalysis.ai/img/logos/maker.svg"
        )
    }

    func testParsesSavedArtificialAnalysisPage() throws {
        let path = fixtureURL("artificial-analysis.html")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path))
        let html = try String(contentsOfFile: path, encoding: .utf8)

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)

        XCTAssertEqual(leaderboard.entries.count, 20)
        XCTAssertTrue(leaderboard.entries.first!.score > leaderboard.entries.last!.score)
        XCTAssertNotNil(leaderboard.sourceNote)
    }

    func testParsesSavedArenaPage() throws {
        let path = fixtureURL("arena-webdev.html")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path))
        let html = try String(contentsOfFile: path, encoding: .utf8)

        let leaderboard = try HTMLLeaderboardParser.arenaWebDev(fromHTML: html)

        XCTAssertEqual(leaderboard.entries.count, 20)
        XCTAssertTrue(leaderboard.entries.first!.score > leaderboard.entries.last!.score)
        XCTAssertNotNil(leaderboard.sourceUpdatedAt)
    }

    private func fixtureURL(_ fileName: String) -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
        return testsDirectory
            .deletingLastPathComponent()
            .appending(path: "work", directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .inferFromPath)
            .path
    }

    private func rscHTML(payload: String, title: String? = nil) -> String {
        let escaped = payload
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let titleTag = title.map { "<title>\($0)</title>" } ?? ""
        return #"<html>\#(titleTag)<script>self.__next_f.push([1,"\#(escaped)"])</script></html>"#
    }
}
