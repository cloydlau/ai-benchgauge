import LeaderboardCore
import XCTest

final class HTMLLeaderboardParserTests: XCTestCase {
    func testParsesArtificialAnalysisTopTwenty() throws {
        let records = (1...22).map { index in
            #"{"slug":"model-\#(index)","name":"Model \#(index)","deprecated":false,"creator":{"name":"Maker","logo":"/img/logos/maker.svg"},"intelligenceIndex":\#(100-index),"intelligenceIndexIsEstimated":false}"#
        }
        let html = #"<html><title>Artificial Analysis Intelligence Index v4.3.2 | Artificial Analysis</title><script>self.__next_f.push([1,"\#(records.joined(separator: ","))"])</script></html>"#

        let leaderboard = try HTMLLeaderboardParser.artificialAnalysis(fromHTML: html)

        XCTAssertEqual(leaderboard.sourceNote, "v4.3.2")
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

    func testParsesArenaTopTwentyAndCutoff() throws {
        let records = (1...22).map { index in
            #"{"rank":\#(index),"modelKey":"arena-model-\#(index)","modelDisplayName":"Arena Model \#(index)","modelOrganization":"Maker","rating":\#(2000-index)}"#
        }
        let html = #"<html><script>self.__next_f.push([1,"{\"leaderboard\":{\"entries\":[\#(records.joined(separator: ","))],\"voteCutoffISOString\":\"2026-09-11T19:00:00.000Z\"}}"])</script></html>"#

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
}
